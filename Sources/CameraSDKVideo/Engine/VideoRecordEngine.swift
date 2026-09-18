//
//  VideoRecordEngine.swift
//  CameraSDKVideo
//
//  The video-specific half of the capture stack. Like `PhotoCaptureEngine`, it's
//  a plain object owned by SwiftUI, and it composes its own
//  `CameraSessionController` for the session, back-camera input, serial queue,
//  and device controls (zoom / focus / torch / lens swap).
//
//  Photo and video build separate controllers, so each screen still runs a
//  private `AVCaptureSession`; only the plumbing source is shared. What's left
//  here is video-only: the movie output, the audio input, the per-category
//  preset, and a 1-second recording timer with optional auto-stop.
//
//  Recording completion is event-driven (it can end from the stop button, the
//  duration limit, or an orientation change), so results are delivered through
//  `recordingHandler` rather than an `async` return.
//

import AVFoundation
import Combine
import UIKit
import CameraSDKCore

@MainActor
final class VideoRecordEngine: NSObject, ObservableObject {

    // MARK: Published UI state

    @Published private(set) var zoomText: String = "1.0x"
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isTorchOn: Bool = false
    @Published private(set) var isUltraWide: Bool = false
    @Published private(set) var isConfigured: Bool = false

    /// Set to `true` while the session reconfigures (e.g. preset change) so the
    /// UI can disable controls briefly.
    @Published private(set) var isBusy: Bool = false

    // MARK: Session

    /// This engine's own session plumbing: session, device, queue, and the
    /// device controls (zoom / focus / torch / lens swap).
    private let controller = CameraSessionController(
        queueLabel: "com.camera-sdk.camera.video.session"
    )

    /// The capture session the preview view renders.
    nonisolated var session: AVCaptureSession { controller.session }

    // The movie output is the one capture object this engine owns outright. It's
    // only touched on the controller's queue, so it sits outside the main
    // actor's isolation like the session objects it joins.
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()

    nonisolated(unsafe) private var currentPreset: AVCaptureSession.Preset
    private var timer: Timer?

    /// Optional hard cap; recording auto-stops when reached.
    var maxDuration: TimeInterval?

    /// Directory recorded movies are written to.
    private let outputDirectory: URL

    /// The video output of a finished recording.
    struct RecordedVideo {
        let url: URL
        let duration: TimeInterval
        let thumbnail: UIImage?
    }

    /// Delivers each finished recording (or an error). Set by the screen.
    var recordingHandler: ((Result<RecordedVideo, Error>) -> Void)?

    // MARK: Init

    init(defaultPreset: AVCaptureSession.Preset, outputDirectory: URL) {
        self.currentPreset = defaultPreset
        self.outputDirectory = outputDirectory
        super.init()
    }

    // MARK: - Lifecycle

    func configure() async throws {
        try await controller.configureSession { [weak self] in
            try self?.configureSessionOnQueue()
        }
        isConfigured = true
    }

    func start() {
        controller.start()
    }

    /// Stops recording (if in flight) and then the session, and cancels the
    /// elapsed-time timer.
    func stop() {
        timer?.invalidate()
        controller.sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
        controller.stop()
    }

    // MARK: - Configuration (session queue)

    /// Adds the video-specific pieces to the session. Runs on the controller's
    /// queue, inside its configuration transaction.
    nonisolated private func configureSessionOnQueue() throws {
        try controller.attachVideoInput(.builtInWideAngleCamera)
        try controller.attachAudioInput()
        try controller.attachOutput(movieOutput)

        session.sessionPreset = currentPreset
    }

    // MARK: - Capabilities

    var supportsUltraWide: Bool {
        CameraSessionController.supportsUltraWide
    }

    var hasTorch: Bool {
        controller.hasTorch
    }

    // MARK: - Preset (per category quality)

    /// Switches the capture preset (e.g. when the selected category changes).
    /// No-op while recording.
    func setPreset(_ preset: AVCaptureSession.Preset) {
        guard preset != currentPreset, !isRecording else { return }
        currentPreset = preset
        isBusy = true
        controller.sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(preset) {
                self.session.sessionPreset = preset
            }
            self.session.commitConfiguration()
            // The new preset resets the format's frame-duration limits, so pin
            // the requested frame rate back on.
            self.controller.reapplyFrameRate()
            Task { @MainActor in self.isBusy = false }
        }
    }

    /// Requests a capture frame rate in fps (clamped to what the format
    /// supports).
    func setFrameRate(_ fps: Int) {
        controller.setFrameRate(fps)
    }

    // MARK: - Zoom / focus

    func setZoom(scale: CGFloat, state: UIGestureRecognizer.State) {
        zoomText = controller.setZoom(scale: scale, state: state)
    }

    func focus(at devicePoint: CGPoint) {
        controller.focus(at: devicePoint)
    }

    // MARK: - Torch

    /// Toggles the torch preference. Returns the new state. The torch is only
    /// physically enabled while recording.
    @discardableResult
    func toggleTorch() -> Bool {
        // Refuse when there's no torch. Without this the published state could
        // read "on" for hardware that has none — the UI then showed a lit torch
        // icon on a device that cannot light anything, and the settings wheel
        // could select On for the same reason.
        guard controller.hasTorch else { return isTorchOn }

        isTorchOn.toggle()
        if isRecording { controller.setTorch(isTorchOn) }
        return isTorchOn
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

    @discardableResult
    func toggleUltraWide() -> Bool {
        guard supportsUltraWide else { return isUltraWide }

        let goingUltra = !isUltraWide
        isUltraWide = goingUltra
        // Only the video input is swapped; the audio input stays in place.
        controller.swapLens(toUltraWide: goingUltra)
        return goingUltra
    }

    // MARK: - Recording

    /// Starts recording to a fresh file, orienting the connection to match how
    /// the device is held.
    func startRecording(orientation: UIDeviceOrientation) {
        guard !movieOutput.isRecording else { return }

        let url = outputDirectory.appendingPathComponent("\(UUID().uuidString).mov")

        controller.sessionQueue.async { [weak self] in
            guard let self else { return }
            self.movieOutput.connection(with: .video)?
                .csSetRotationAngle(orientation.csCaptureRotationAngle)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            Task { @MainActor in self.controller.setTorch(self.isTorchOn) }
        }
    }

    /// Stops the current recording.
    func stopRecording() {
        guard movieOutput.isRecording else { return }
        controller.sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        elapsedSeconds = 0
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsedSeconds += 1
                if let max = self.maxDuration, Double(self.elapsedSeconds) >= max {
                    self.stopRecording()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedSeconds = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Generates a first-frame thumbnail for a recorded movie.
    private nonisolated func makeThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        return await withCheckedContinuation { cont in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, _, _ in
                cont.resume(returning: image.map(UIImage.init))
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecordEngine: AVCaptureFileOutputRecordingDelegate {

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor [weak self] in
            self?.isRecording = true
            self?.startTimer()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.stopTimer()
            self.controller.setTorch(false)

            if let error {
                self.recordingHandler?(
                    .failure(CSCameraError.videoRecordingFailed(error.localizedDescription))
                )
                return
            }

            let asset = AVURLAsset(url: outputFileURL)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let thumbnail = await self.makeThumbnail(for: outputFileURL)

            self.recordingHandler?(
                .success(RecordedVideo(url: outputFileURL, duration: duration, thumbnail: thumbnail))
            )
        }
    }
}
