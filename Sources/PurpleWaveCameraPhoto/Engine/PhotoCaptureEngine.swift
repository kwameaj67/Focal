//
//  PhotoCaptureEngine.swift
//  PurpleWaveCameraPhoto
//
//  The photo-specific half of the capture stack. This is a plain object (not a
//  view controller) so the SwiftUI layer can own it as an `@StateObject`. It
//  owns the photo output and exposes published state the UI binds to.
//
//  Everything session-shaped — the `AVCaptureSession`, the back-camera input,
//  the serial queue, zoom / focus / lens swapping — lives in
//  `CameraSessionController`, which this composes. Each engine builds its *own*
//  controller, so each still owns a private session; only the source is shared.
//  What's left here is genuinely photo-only: the output, per-shot settings,
//  flash, and delivery.
//
//  Threading model: all `AVCaptureSession` mutation happens on the controller's
//  serial queue; all `@Published` mutation happens on the main actor. Photo
//  delivery is bridged to `async` via a continuation.
//

import AVFoundation
import Combine
import CoreImage
import UIKit
import PurpleWaveCameraCore

@MainActor
final class PhotoCaptureEngine: NSObject, ObservableObject {

    // MARK: Published UI state

    /// Zoom label text, e.g. "1.0x". Driven by pinch.
    @Published private(set) var zoomText: String = "1.0x"

    /// `true` while a capture is in flight; the UI disables the shutter.
    @Published private(set) var isProcessing: Bool = false

    /// Current flash mode (bindable so the flash menu reflects reality).
    @Published var flashMode: PWFlashMode

    /// Whether the ultra-wide lens is currently active.
    @Published private(set) var isUltraWide: Bool = false

    /// `true` once the session is configured and safe to preview.
    @Published private(set) var isConfigured: Bool = false

    // MARK: Session

    /// This engine's own session plumbing: session, device, queue, and the
    /// device controls (zoom / focus / lens swap).
    private let controller = CameraSessionController(
        queueLabel: "com.purplewave.camera.photo.session"
    )

    /// The capture session the preview view renders.
    nonisolated var session: AVCaptureSession { controller.session }

    // The photo output is the one capture object this engine owns outright. It's
    // only touched on the controller's queue, so it sits outside the main
    // actor's isolation like the session objects it joins.
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()

    /// Continuation resumed when the current capture's data arrives.
    private var captureContinuation: CheckedContinuation<CapturedPhoto, Error>?

    /// Bundle of the encoded data + decoded image + metadata for one capture.
    struct CapturedPhoto {
        let data: Data
        let image: UIImage
        let metadata: [String: Any]?
    }

    // MARK: Init

    init(defaultFlashMode: PWFlashMode) {
        self.flashMode = defaultFlashMode
        super.init()
    }

    // MARK: - Lifecycle

    /// Configures inputs/outputs. Call once before starting the session.
    /// - Throws: `PWCameraError.sessionConfigurationFailed` if no camera is
    ///   available or an input can't be added.
    func configure() async throws {
        try await controller.configureSession { [weak self] in
            try self?.configureSessionOnQueue()
        }
        isConfigured = true
    }

    /// Starts the capture session (no-op if already running).
    func start() {
        controller.start()
    }

    /// Stops the capture session.
    func stop() {
        controller.stop()
    }

    // MARK: - Configuration (session queue)

    /// Adds the photo-specific pieces to the session. Runs on the controller's
    /// queue, inside its configuration transaction.
    nonisolated private func configureSessionOnQueue() throws {
        session.sessionPreset = .photo

        try controller.attachVideoInput(.builtInWideAngleCamera)
        try controller.attachOutput(photoOutput)

        // Opt into the sensor's full resolution (iOS 16 replacement for the
        // deprecated `isHighResolutionCaptureEnabled`). `settings.maxPhotoDimensions`
        // then mirrors this per shot in `makeSettings(flash:)`.
        if let maxDimensions = controller.activeFormat?.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = maxDimensions
        }

        // Keep the preview upright; capture orientation is set per-shot.
        photoOutput.connection(with: .video)?.videoOrientation = .portrait
    }

    // MARK: - Capabilities

    /// Whether the device has an ultra-wide lens to switch to.
    var supportsUltraWide: Bool {
        CameraSessionController.supportsUltraWide
    }

    // MARK: - Zoom / focus

    /// Applies a pinch zoom. Clamps between 1× and 5×.
    /// - Parameters:
    ///   - scale: the gesture's current scale.
    ///   - state: gesture state; the factor is committed on `.ended`.
    func setZoom(scale: CGFloat, state: UIGestureRecognizer.State) {
        zoomText = controller.setZoom(scale: scale, state: state)
    }

    /// Focuses and exposes at a device point produced by the preview layer.
    func focus(at devicePoint: CGPoint) {
        controller.focus(at: devicePoint)
    }

    // MARK: - Exposure

    /// The device's supported exposure-bias range in EV, or `nil` when the
    /// device can't report one.
    var exposureBiasRange: ClosedRange<Float>? {
        controller.exposureBiasRange
    }

    /// Applies an exposure-bias offset in EV.
    func setExposureBias(_ bias: Float) {
        controller.setExposureBias(bias)
    }

    // MARK: - Ultra-wide switching

    /// Toggles between the wide and ultra-wide back cameras. Returns the new
    /// state (`true` == ultra-wide) for UI feedback.
    @discardableResult
    func toggleUltraWide() -> Bool {
        guard supportsUltraWide else { return isUltraWide }

        let goingUltra = !isUltraWide
        isUltraWide = goingUltra
        controller.swapLens(toUltraWide: goingUltra)
        return goingUltra
    }

    // MARK: - Capture

    /// Captures a single photo for the given device orientation.
    /// - Returns: encoded data + a decoded `UIImage` + metadata.
    /// - Throws: `PWCameraError.photoCaptureFailed` on any failure.
    func capturePhoto(orientation: UIDeviceOrientation) async throws -> CapturedPhoto {
        guard !isProcessing else {
            throw PWCameraError.photoCaptureFailed("Capture already in progress")
        }
        isProcessing = true
        defer { isProcessing = false }

        // Snapshot the main-actor state we need before hopping to the session
        // queue, so the queue closure touches only non-isolated objects.
        let captureOrientation = orientation.pwCaptureVideoOrientation
        let flash = flashMode.avFlashMode

        return try await withCheckedThrowingContinuation { cont in
            self.captureContinuation = cont
            controller.sessionQueue.async { [weak self] in
                guard let self else { return }
                guard self.session.isRunning,
                      let connection = self.photoOutput.connection(with: .video),
                      connection.isEnabled else {
                    Task { @MainActor in
                        self.finishCapture(
                            .failure(PWCameraError.photoCaptureFailed("Session not ready"))
                        )
                    }
                    return
                }

                // Match capture orientation to how the device is held. Setting
                // the connection and capturing are both safe off the main thread.
                connection.preferredVideoStabilizationMode = .off
                connection.videoOrientation = captureOrientation
                self.photoOutput.capturePhoto(with: self.makeSettings(flash: flash), delegate: self)
            }
        }
    }

    /// Builds per-shot photo settings (HEVC when available, the given flash
    /// mode, a "fieldtool_captured" EXIF marker, and max resolution). Runs on
    /// the session queue, so it must not touch main-actor state.
    nonisolated private func makeSettings(flash: AVCaptureDevice.FlashMode) -> AVCapturePhotoSettings {
        var settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        settings.flashMode = flash

        // Some iPads crash if an unsupported flash mode is requested.
        if !photoOutput.supportedFlashModes.contains(flash) {
            settings.flashMode = .off
        }

        settings.metadata = [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifUserComment as String: "fieldtool_captured"
            ]
        ]

        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        return settings
    }

    /// Resumes the pending capture continuation exactly once.
    private func finishCapture(_ result: Result<CapturedPhoto, Error>) {
        guard let cont = captureContinuation else { return }
        captureContinuation = nil
        cont.resume(with: result)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoCaptureEngine: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Decode off the main thread, then resume the continuation on main.
        let outcome: Result<CapturedPhoto, Error>
        if let error {
            outcome = .failure(PWCameraError.photoCaptureFailed(error.localizedDescription))
        } else if let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) {
            outcome = .success(CapturedPhoto(data: data, image: image, metadata: photo.metadata))
        } else {
            outcome = .failure(PWCameraError.photoCaptureFailed("No image data"))
        }

        Task { @MainActor [weak self] in
            self?.finishCapture(outcome)
        }
    }
}
