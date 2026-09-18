//
//  CameraSessionController.swift
//  FocalCore
//
//  The capture-session plumbing shared by `PhotoCaptureEngine` and
//  `VideoRecordEngine`: the `AVCaptureSession` itself, the active back-camera
//  input, the serial queue every mutation runs on, and the controls that only
//  need a locked `AVCaptureDevice` (zoom, focus/exposure, torch, lens swap).
//
//  The engines *compose* this rather than subclassing it: each one owns its own
//  output (`AVCapturePhotoOutput` / `AVCaptureMovieFileOutput`), its own
//  delegate conformance, and all of its `@Published` UI state. This type holds
//  no observable state and is deliberately not an `ObservableObject` — nested
//  observable objects don't propagate `objectWillChange` through SwiftUI, so
//  published state stays on the engine that owns the screen.
//
//  Threading model (inherited by both engines):
//    • Every `AVCaptureSession` / `AVCaptureDevice` mutation happens on
//      `sessionQueue`, a serial queue. Methods that must already be on it are
//      marked `nonisolated` and say so in their doc comment.
//    • `AVFoundation` types aren't `Sendable`, so the session objects are
//      `nonisolated(unsafe)`; the serial queue provides the synchronization.
//
//  Access: `package`, not `public`. The photo and video targets each build
//  their own instance, so this has to cross a module boundary — but it is
//  plumbing, not something hosts should program against, so splitting the
//  package into targets did not add it to the public API.
//

import AVFoundation
import UIKit

@MainActor
package final class CameraSessionController {

    // MARK: Session objects

    /// The capture session the preview layer renders. Handing this to
    /// `AVCaptureVideoPreviewLayer` is safe from any thread.
    package nonisolated(unsafe) let session = AVCaptureSession()

    /// The active back-camera input, swapped when toggling ultra-wide.
    nonisolated(unsafe) private var videoInput: AVCaptureDeviceInput?

    /// The device backing `videoInput`. Every control below locks this.
    nonisolated(unsafe) private var device: AVCaptureDevice?

    /// The frame rate the host asked for, re-applied after any device or format
    /// change (a lens swap or preset change resets the device's frame-duration
    /// limits). `nil` until a rate is requested.
    nonisolated(unsafe) private var desiredFrameRate: Int?

    /// Serial queue for all session configuration and control. Engines dispatch
    /// their own output work here too, so ordering is preserved end to end.
    package nonisolated let sessionQueue: DispatchQueue

    // MARK: Zoom state

    /// Zoom committed by completed pinch gestures; in-flight pinches multiply
    /// against it without mutating it until the gesture ends.
    private var zoomFactor: CGFloat = 1.0

    /// Pinch zoom is clamped to this range.
    private let zoomRange: ClosedRange<CGFloat> = 1.0...5.0

    // MARK: Init

    /// - Parameter queueLabel: label for the serial session queue, e.g.
    ///   `"com.focal.camera.photo.session"`. Distinct labels keep the two
    ///   engines legible in a thread backtrace.
    package init(queueLabel: String) {
        sessionQueue = DispatchQueue(label: queueLabel)
    }

    // MARK: - Lifecycle

    /// Hops to `sessionQueue` and runs `body` inside a
    /// `beginConfiguration`/`commitConfiguration` pair, then resumes.
    ///
    /// Each engine passes its own body to add the output it owns. The
    /// configuration is always committed, including when `body` throws, so the
    /// session is never left mid-transaction.
    ///
    /// - Throws: whatever `body` throws.
    package func configureSession(_ body: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else { return cont.resume() }
                self.session.beginConfiguration()
                let outcome = Result { try body() }
                self.session.commitConfiguration()
                cont.resume(with: outcome)
            }
        }
    }

    /// Starts the capture session (no-op if already running).
    package func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    /// Stops the capture session (no-op if not running). Engines with extra
    /// teardown — a recording in flight, a timer — do it around this call.
    package func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Inputs

    /// Makes the back camera of `deviceType` the session's video input,
    /// removing whatever input was there before.
    ///
    /// Must be called on `sessionQueue`, inside a configuration transaction.
    ///
    /// - Throws: `FCCameraError.sessionConfigurationFailed` if the device is
    ///   missing or the input can't be added. On failure the previous input is
    ///   restored, so a failed lens swap leaves a working session.
    package nonisolated func attachVideoInput(_ deviceType: AVCaptureDevice.DeviceType) throws {
        guard let target = AVCaptureDevice.default(deviceType, for: .video, position: .back) else {
            throw FCCameraError.sessionConfigurationFailed("No back camera available")
        }

        let input = try AVCaptureDeviceInput(device: target)
        let previous = videoInput
        if let previous { session.removeInput(previous) }

        guard session.canAddInput(input) else {
            if let previous { session.addInput(previous) }
            throw FCCameraError.sessionConfigurationFailed("Cannot add camera input")
        }

        session.addInput(input)
        videoInput = input
        device = target

        // A new device starts at its format's default frame duration, so
        // re-assert the requested rate (no-op until one has been set).
        applyFrameRateLocked()
    }

    /// Adds `output` to the session.
    ///
    /// Must be called on `sessionQueue`, inside a configuration transaction.
    ///
    /// - Throws: `FCCameraError.sessionConfigurationFailed` if it can't be added.
    package nonisolated func attachOutput(_ output: AVCaptureOutput) throws {
        guard session.canAddOutput(output) else {
            throw FCCameraError.sessionConfigurationFailed("Cannot add capture output")
        }
        session.addOutput(output)
    }

    // MARK: - Capabilities

    /// Whether this device has an ultra-wide back lens to switch to. Static
    /// because it depends only on the hardware, not on session state.
    package static var supportsUltraWide: Bool {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
    }

    /// Whether the *currently active* lens has a torch.
    package nonisolated var hasTorch: Bool {
        device?.hasTorch ?? false
    }

    /// The active lens's current format, for read-only inspection of what the
    /// hardware supports (e.g. the photo engine reading
    /// `supportedMaxPhotoDimensions`). Mutating the device requires the lock,
    /// so this deliberately isn't a route to configuration.
    package nonisolated var activeFormat: AVCaptureDevice.Format? {
        device?.activeFormat
    }

    // MARK: - Device controls

    /// Applies a pinch zoom, clamped to `zoomRange`, committing the factor when
    /// the gesture ends.
    ///
    /// - Returns: the display label for the new factor, e.g. `"2.4x"`. The
    ///   caller publishes it; this type holds no observable state.
    @discardableResult
    package func setZoom(scale: CGFloat, state: UIGestureRecognizer.State) -> String {
        let target = min(max(scale * zoomFactor, zoomRange.lowerBound), zoomRange.upperBound)
        if state == .ended { zoomFactor = target }

        sessionQueue.async { [weak self] in
            self?.withLockedDevice { $0.videoZoomFactor = target }
        }

        return String(format: "%.1fx", target)
    }

    /// Focuses and exposes at a device point produced by the preview layer.
    package func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            self?.withLockedDevice { device in
                if device.isFocusPointOfInterestSupported,
                   device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
        }
    }

    // MARK: - Exposure

    /// The device's supported exposure-bias range in EV, or `nil` with no
    /// active device. Typically around ±8 but genuinely device-specific, so the
    /// UI must read it rather than assume.
    package nonisolated var exposureBiasRange: ClosedRange<Float>? {
        guard let device else { return nil }
        return device.minExposureTargetBias...device.maxExposureTargetBias
    }

    /// Applies an exposure-bias offset in EV, clamped to what the device
    /// supports.
    ///
    /// Note this fights tap-to-focus: `focus(at:)` sets `.autoExpose`, which
    /// re-meters and effectively discards the bias. Callers that expose both
    /// controls need to decide which wins — the screens here re-apply the bias
    /// after a focus tap so the user's explicit choice survives.
    package func setExposureBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let range = self.exposureBiasRange else { return }
            let clamped = min(max(bias, range.lowerBound), range.upperBound)
            self.withLockedDevice { device in
                device.setExposureTargetBias(clamped, completionHandler: nil)
            }
        }
    }

    /// Requests a capture frame rate (in fps), clamped to what the active format
    /// supports, and remembers it so it survives later device/format changes.
    package func setFrameRate(_ fps: Int) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.desiredFrameRate = fps
            self.applyFrameRateLocked()
        }
    }

    /// Re-applies the last requested frame rate. Call after a preset change,
    /// which resets the device's frame-duration limits. (Lens swaps re-apply on
    /// their own, via `attachVideoInput`.)
    package func reapplyFrameRate() {
        sessionQueue.async { [weak self] in
            self?.applyFrameRateLocked()
        }
    }

    /// Pins the active device to `desiredFrameRate`, clamped to the highest rate
    /// the active format supports. Must be called on `sessionQueue`.
    nonisolated fileprivate func applyFrameRateLocked() {
        guard let fps = desiredFrameRate, let device else { return }
        let supportedMax = device.activeFormat.videoSupportedFrameRateRanges
            .map(\.maxFrameRate).max() ?? 30
        // Clamp to what the format can actually deliver, so an unsupported 60fps
        // request falls back to (say) 30 rather than throwing.
        let target = Int(min(Double(fps), supportedMax).rounded())
        guard target > 0 else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(target))
        withLockedDevice { device in
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    /// Turns the torch on the active lens on or off. No-op without a torch.
    package func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            self?.withLockedDevice { device in
                guard device.hasTorch else { return }
                device.torchMode = on ? .on : .off
            }
        }
    }

    /// Swaps between the wide and ultra-wide back lenses, keeping every other
    /// input and output in place. Best-effort: if the swap fails,
    /// `attachVideoInput` restores the previous lens.
    package func swapLens(toUltraWide: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            try? self.attachVideoInput(
                toUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
            )
        }
    }

    // MARK: - Device locking

    /// Runs `body` with the active device locked for configuration, then
    /// unlocks it.
    ///
    /// Every caller here is best-effort, so a missing device or a failed lock
    /// is silently ignored. Critically, `body` runs *only* if the lock was
    /// taken: mutating an `AVCaptureDevice` without holding its lock — or
    /// calling `unlockForConfiguration()` when the lock was never acquired — is
    /// API misuse.
    ///
    /// Must be called on `sessionQueue`.
    nonisolated fileprivate func withLockedDevice(_ body: (AVCaptureDevice) -> Void) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
        } catch {
            return
        }
        body(device)
        device.unlockForConfiguration()
    }
}
