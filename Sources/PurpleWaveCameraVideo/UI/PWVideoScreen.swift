//
//  PWVideoScreen.swift
//  PurpleWaveCameraVideo
//
//  The public SwiftUI video recorder. Rebuilds the FieldTool recorder: live
//  preview, torch, gallery import, ultra-wide toggle, pinch-zoom, tap-to-focus,
//  a category segmented control, a recording timer, and a record button.
//
//  Recording is **landscape-only**: in portrait the screen dims and shows a
//  "rotate to landscape" overlay, and the record button is disabled — matching
//  the second screenshot.
//

import Photos
import SwiftUI
import Transmission
import PurpleWaveCameraCore

public struct PWVideoScreen: View {

    // MARK: Inputs

    private let config: PWVideoConfig
    private let handlers: PWVideoHandlers

    // MARK: State

    @StateObject private var engine: VideoRecordEngine
    @StateObject private var orientation = DeviceOrientationMonitor()

    @State private var selectedCategory: PWCategory?
    @State private var showGallery = false
    @State private var focusPoint: CGPoint?
    @State private var deniedPermission: PWPermission?
    @State private var didRecordAny = false

    /// All clips this session (recorded + imported), oldest → newest. Drives the
    /// stacked thumbnail pile and the full-screen gallery preview.
    @State private var recorded: [CapturedVideoItem] = []
    /// Guards one-time configuration across re-appearances (e.g. returning from
    /// the full-screen preview).
    @State private var didSetUp = false

    // Drives the "recorded video drops into the thumbnail" animation.
    @State private var dropImage: UIImage?
    @State private var dropProgress: CGFloat = 0

    // Capture settings sheet.
    @State private var showSettings = false
    @State private var settingsPane: CaptureSettingsPane = .grid
    @State private var aspectRatio: PWAspectRatio = .sixteenNine
    @State private var captureTimer: PWCaptureTimer = .off
    @State private var exposureBias: Float = 0
    /// Non-nil while the self-timer counts down before recording starts.
    @State private var countdown: Int?
    /// Whether the aspect/badge info tip is showing. Toggled by the info icon
    /// in the top bar.
    @State private var showInfoTip = false

    // MARK: Init

    /// Creates a video recorder screen.
    public init(config: PWVideoConfig, handlers: PWVideoHandlers) {
        self.config = config
        self.handlers = handlers
        let dir = OutputDirectory.resolve(config.outputDirectory)
        _engine = StateObject(wrappedValue: VideoRecordEngine(
            defaultPreset: config.preset(for: config.initialCategory).avPreset,
            outputDirectory: dir
        ))
        _selectedCategory = State(initialValue: config.initialCategory)
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let deniedPermission {
                PermissionDeniedView(permission: deniedPermission) {
                    handlers.onFinish(.cancelled)
                }
            } else {
                preview
                overlays

                // Portrait guard: block recording until the device is rotated.
                if !orientation.orientation.pwIsLandscape {
                    RotateToLandscapeOverlay(onHelpTapped: nil)
                }
            }
        }
        // Reads the live thumbnail position so the recording "drop" animation
        // knows where to land, then renders the flying image.
        .overlayPreferenceValue(ThumbnailAnchorKey.self) { anchor in
            DropFlightOverlay(image: dropImage, progress: dropProgress, anchor: anchor)
        }
        .statusBarHidden(true)
        .task { await setUp() }
        // Resume the session when the screen re-appears (e.g. after dismissing
        // the full-screen video preview) so the live feed doesn't stay frozen.
        .overlay {
            CaptureSettingsOverlay(isPresented: $showSettings) {
                settingsSheet
            }
        }
        .onAppear { if engine.isConfigured { engine.start(); orientation.start() } }
        .onDisappear { engine.stop(); orientation.stop() }
        .onChange(of: selectedCategory) { _ , newValue in
            engine.setPreset(config.preset(for: newValue).avPreset)
        }
        .sheet(isPresented: $showGallery) { galleryScreen }
    }

    // MARK: - Preview

    private var preview: some View {
        CameraPreviewView(
            session: engine.session,
            onTapToFocus: { devicePoint, touchPoint in
                engine.focus(at: devicePoint)
                HapticsManager.shared.selection()
                withAnimation { focusPoint = touchPoint }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { focusPoint = nil }
                }
            },
            onPinch: { scale, state in engine.setZoom(scale: scale, state: state) },
            // Hardware volume buttons start/stop recording (iOS 17.2+).
            onHardwareShutter: { toggleRecording() }
        )
        // Framing only. Unlike the photo path, the recorded file is NOT cropped
        // to this ratio — doing so would mean re-encoding the movie, which is
        // slow and lossy. The recorder writes whatever the session preset
        // produces, so treat this as a composition guide.
        .aspectRatio(
            aspectRatio.ratio(isLandscape: orientation.orientation.pwIsLandscape),
            contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let focusPoint { FocusSquare(point: focusPoint) }
        }
        .overlay {
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
                    .id(countdown)
            }
        }
    }

    // MARK: - Capture settings

    private var settingsButton: some View {
        Button {
            HapticsManager.shared.tap()
            settingsPane = .grid
            withAnimation(CaptureSettingsOverlay<EmptyView>.motion) { showSettings = true }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.black.opacity(0.3)))
                .rotationEffect(.radians(orientation.angle))
        }
        .disabled(engine.isRecording)
        .accessibilityLabel("Capture settings")
    }

    /// Torch stands in for flash here — the recorder has a continuous light,
    /// not a strobe — so the grid's first tile differs from the photo screen's.
    private var settingsTiles: [CaptureSettingsTile] {
        var tiles: [CaptureSettingsTile] = [
            CaptureSettingsTile(
                id: "torch", pane: .flash,
                systemImage: engine.isTorchOn ? "bolt.fill" : "bolt.slash",
                title: "Torch",
                isActive: engine.isTorchOn
            ),
            CaptureSettingsTile(
                id: "aspect", pane: .aspectRatio, systemImage: "aspectratio",
                title: "Aspect",
                // 16:9 is the recorder's native shape here, unlike the photo
                // screen where the sensor gives 4:3.
                isActive: aspectRatio != .sixteenNine
            ),
            CaptureSettingsTile(
                id: "timer", pane: .timer, systemImage: "timer",
                title: "Timer",
                isActive: captureTimer.isOn,
                displayText: captureTimer.isOn ? captureTimer.title : nil
            ),
            CaptureSettingsTile(
                id: "exposure", pane: .exposure, systemImage: "sun.max",
                title: "Exposure",
                isActive: exposureBias != 0
            )
        ]
        // Only offer the lens switch where there's a second lens to switch to,
        // matching the top-bar button's condition. Devices without an
        // ultra-wide get a four-tile grid rather than a dead control.
        if config.allowsUltraWide && engine.supportsUltraWide {
            tiles.append(
                CaptureSettingsTile(
                    id: "lens", pane: .lens,
                    systemImage: engine.isUltraWide ? "camera.aperture" : "camera",
                    title: "Lens",
                    isActive: engine.isUltraWide
                )
            )
        }
        return tiles
    }

    @ViewBuilder
    private var settingsSheet: some View {
        switch settingsPane {
        case .grid:
            CaptureSettingsChrome(title: "Settings") {
                CaptureSettingsGrid(tiles: settingsTiles) { pane in
                    withAnimation(CaptureSettingsOverlay<EmptyView>.motion) { settingsPane = pane }
                }
            }

        case .flash:
            CaptureSettingsChrome(title: "Torch", onBack: backToGrid) {
                DiscreteWheel(
                    values: [true, false],
                    selection: Binding(
                        get: { engine.isTorchOn },
                        set: { wantsOn in
                            if wantsOn != engine.isTorchOn { engine.toggleTorch() }
                        }
                    ),
                    title: { $0 ? "On" : "Off" }
                )
            }

        case .aspectRatio:
            CaptureSettingsChrome(title: "Aspect Ratio", onBack: backToGrid) {
                AspectRatioSelector(selection: $aspectRatio)
            }

        case .timer:
            CaptureSettingsChrome(title: "Timer", onBack: backToGrid) {
                DiscreteWheel(
                    values: PWCaptureTimer.allCases,
                    selection: $captureTimer,
                    title: \.title
                )
            }

        case .lens:
            CaptureSettingsChrome(title: "Lens", onBack: backToGrid) {
                DiscreteWheel(
                    values: [false, true],
                    selection: Binding(
                        get: { engine.isUltraWide },
                        // The engine exposes a toggle rather than a setter, so
                        // only act when the wheel actually moves to the other
                        // lens — otherwise re-selecting the current one would
                        // swap it away.
                        set: { wantsUltra in
                            if wantsUltra != engine.isUltraWide { engine.toggleUltraWide() }
                        }
                    ),
                    title: { $0 ? "Ultra Wide" : "Normal" }
                )
            }

        case .exposure:
            CaptureSettingsChrome(title: "Exposure", onBack: backToGrid) {
                if let range = engine.exposureBiasRange {
                    ExposureWheel(value: $exposureBias, range: range)
                        .onChange(of: exposureBias) { _, bias in
                            engine.setExposureBias(bias)
                        }
                } else {
                    Text("Exposure adjustment is unavailable on this device.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                }
            }
        }
    }

    private func backToGrid() {
        withAnimation(CaptureSettingsOverlay<EmptyView>.motion) { settingsPane = .grid }
    }

    // MARK: - Overlays

    private var overlays: some View {
        VStack(spacing: 0) {
            topBar
                // Anchored under the bar's trailing edge so the caret lands on
                // the info icon.
                .overlay(alignment: .topTrailing) {
                    if showInfoTip {
                        infoTip
                            .padding(.top, 46)
                            .padding(.trailing, 52)
                    }
                }
                .zIndex(1)   // the tip must draw over the preview below it

            timerPill

            Spacer()
            ZoomBadge(text: engine.zoomText, rotation: orientation.angle)
                .padding(.bottom, 8)
            if !config.categories.isEmpty {
                // Same selector as the photo screen: centered pills, swipe to
                // step between categories, tap to jump.
                CategoryScrollBar(
                    categories: config.categories,
                    selected: $selectedCategory
                )
                .disabled(engine.isRecording)
            }
            bottomControls
        }
        .padding(.vertical, 12)
    }

    private var topBar: some View {
        HStack {
            // Always rendered when the host allows a torch, so the top-left
            // always shows torch state — matching the photo screen, whose flash
            // control isn't hardware-gated either. Previously this was hidden
            // whenever `hasTorch` was false, which left the corner empty on any
            // device without a torch and made the two screens look different.
            if config.allowsTorch {
                iconButton(
                    systemName: engine.isTorchOn ? "bolt.fill" : "bolt.slash",
                    tint: engine.isTorchOn ? .yellow : .white
                ) { engine.toggleTorch(); HapticsManager.shared.tap() }
                    .disabled(!engine.hasTorch)
                    .opacity(engine.hasTorch ? 1 : 0.4)
            }

            Spacer()

            if config.allowsUltraWide && engine.supportsUltraWide {
                iconButton(
                    systemName: engine.isUltraWide ? "camera.aperture" : "camera",
                    tint: engine.isUltraWide ? .yellow : .white
                ) { engine.toggleUltraWide(); HapticsManager.shared.impact() }
            }
            if config.allowsGallery {
                iconButton(systemName: "photo.on.rectangle") {
                    HapticsManager.shared.tap()
                    openGallery()
                }
                .disabled(engine.isRecording)
            }
            infoButton
            settingsButton
        }
        .padding(.horizontal, 20)
    }

    /// Toggles the info tip. Filled while open so the icon reads as a state,
    /// not just a button.
    private var infoButton: some View {
        iconButton(
            systemName: showInfoTip ? "info.circle.fill" : "info.circle",
            tint: showInfoTip ? .yellow : .white
        ) {
            HapticsManager.shared.tap()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                showInfoTip.toggle()
            }
        }
    }

    /// Aspect framing and the item badge, shown on demand rather than parked
    /// permanently over the viewfinder — matching the photo screen.
    private var infoTip: some View {
        InfoTip {
            VStack(alignment: .leading, spacing: 4) {
                Text(aspectRatio.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                if let label = config.overlayLabel {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    /// Elapsed-time pill. Sits below the bar rather than in it: centring it
    /// between two Spacers made its width push the surrounding controls around
    /// as the digits changed.
    private var timerPill: some View {
        Text(timerString)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(timerBackground)
            .cornerRadius(5)
            .padding(.top, 8)
    }

    private var bottomControls: some View {
        HStack {
            Button("Cancel") {
                handlers.onFinish(didRecordAny ? .done : .cancelled)
            }
            .font(.system(size: 17))
            .foregroundColor(.white)
            .disabled(engine.isRecording)

            Spacer()

            RecordButton(isRecording: engine.isRecording,
                         isEnabled: orientation.orientation.pwIsLandscape && !engine.isBusy) {
                toggleRecording()
            }

            Spacer()

            thumbnailPreviewLink
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// The stacked pile of recent clips. When there's at least one, tapping it
    /// presents the full-screen gallery preview via Transmission's zoom
    /// transition; the anchor reports its frame for the drop animation.
    @ViewBuilder
    private var thumbnailPreviewLink: some View {
        if recorded.isEmpty {
            stackThumbnail
        } else {
            PresentationLink(transition: .zoomIfAvailable) {
                CapturedVideoGalleryPreview(items: recorded, startIndex: recorded.count - 1)
            } label: {
                stackThumbnail
            }
            .buttonStyle(.plain)
            .disabled(engine.isRecording)
        }
    }

    private var stackThumbnail: some View {
        CapturedStackThumbnail(images: recorded.compactMap(\.thumbnail))
            .thumbnailAnchor()
    }

    // MARK: - Timer formatting

    private var timerString: String {
        let s = engine.elapsedSeconds
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// The timer pill changes colour each minute (green → yellow → red) like the
    /// FieldTool recorder.
    private var timerBackground: Color {
        guard engine.isRecording else { return .black.opacity(0.4) }
        switch (engine.elapsedSeconds / 60) % 3 {
        case 0:  return .green.opacity(0.7)
        case 1:  return .yellow.opacity(0.7)
        default: return .red.opacity(0.7)
        }
    }

    private func iconButton(
        systemName: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Gallery

    /// Requests photo-library access, then presents the picker only if it was
    /// granted.
    ///
    /// Asked here rather than at screen setup so declining the library costs
    /// the user the gallery button, not the camera. A denial is reported
    /// through `onError` so the host knows why nothing opened, but the capture
    /// screen stays usable.
    private func openGallery() {
        Task {
            if await MediaPermissions.requestPhotoLibrary() {
                showGallery = true
            } else {
                handlers.onError(.permissionDenied(.photoLibrary))
            }
        }
    }


    private var galleryScreen: some View {
        MediaGalleryScreen(
            mediaType: .video,
            onDone: { assets in
                showGallery = false
                importVideos(assets)
            },
            onCancel: { showGallery = false }
        )
    }

    // MARK: - Actions

    private func setUp() async {
        // `.task` re-runs on every appearance; only configure the session once.
        guard !didSetUp else { return }
        didSetUp = true

        // Bring the haptic engine up once, here — not in the SwiftUI `init`.
        HapticsManager.shared.setupHapticEngine()
        HapticsManager.shared.addObservers()

        // The preview canvas has no camera or microphone and nowhere to present
        // a permission prompt, so the requests below would leave the screen
        // stuck on its denied state — and requesting the microphone in a host
        // without NSMicrophoneUsageDescription is fatal. Stop here and let the
        // chrome render over an empty preview layer, which is what the canvas is
        // useful for. The photo screen has always done this; the video screen
        // was missing it, which is why only its previews were unusable.
        guard !ProcessInfo.isRunningInXcodePreview else { return }

        // Ask up front rather than when a recording finishes, so the prompt
        // never lands mid-take. A denial is not fatal — clips just carry no
        // location.
        if config.capturesLocation {
            await LocationManager.shared.requestAuthorization()
        }

        engine.maxDuration = config.maxDuration
        engine.recordingHandler = handleRecording

        if let denied = await MediaPermissions.ensureVideoPermissions() {
            deniedPermission = denied
            didSetUp = false   // allow a retry if the user grants access and returns
            handlers.onError(.permissionDenied(denied))
            return
        }
        do {
            try await engine.configure()
            engine.start()
            orientation.start()
        } catch {
            handlers.onError(error as? PWCameraError
                             ?? .sessionConfigurationFailed(error.localizedDescription))
        }
    }

    private func toggleRecording() {
        // A countdown in flight swallows further presses, so a second tap can't
        // start two recordings.
        guard countdown == nil else { return }

        // The timer delays *starting* only. Applying it to stop would mean the
        // user watches a countdown while the camera keeps recording, which is
        // the opposite of what they asked for.
        if !engine.isRecording, captureTimer.isOn,
           orientation.orientation.pwIsLandscape, !engine.isBusy {
            HapticsManager.shared.impact()
            Task {
                for remaining in stride(from: captureTimer.rawValue, through: 1, by: -1) {
                    withAnimation(.easeOut(duration: 0.15)) { countdown = remaining }
                    HapticsManager.shared.tap()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                withAnimation { countdown = nil }
                // Re-check: the device may have been rotated out of landscape
                // during the countdown.
                if orientation.orientation.pwIsLandscape, !engine.isBusy {
                    engine.startRecording(orientation: orientation.orientation)
                }
            }
            return
        }

        if engine.isRecording {
            engine.stopRecording()
            HapticsManager.shared.impact()
        } else if orientation.orientation.pwIsLandscape && !engine.isBusy {
            // Only start in landscape (mirrors the record button being disabled
            // in portrait), so the volume-button path can't start a portrait clip.
            engine.startRecording(orientation: orientation.orientation)
            HapticsManager.shared.impact()
        }
    }

    /// Handles a finished recording from the engine.
    private func handleRecording(_ result: Result<VideoRecordEngine.RecordedVideo, Error>) {
        switch result {
        case .success(let video):
            didRecordAny = true
            let item = CapturedVideoItem(
                thumbnail: video.thumbnail, url: video.url,
                category: selectedCategory, source: .camera
            )
            performDrop(flying: video.thumbnail, commit: item)
            // Fire and forget: saving must not delay onRecord, and the add
            // permission prompt would otherwise sit between the user finishing
            // a recording and the host hearing about it.
            if config.savesToPhotoLibrary {
                Task {
                    if await PhotoLibrarySaver.ensureAddPermission() {
                        PhotoLibrarySaver.save(videoURL: video.url)
                    }
                }
            }
            let capturedAt = Date()
            Task {
                let location = config.capturesLocation
                    ? await LocationManager.shared.currentLocation()
                    : nil

                handlers.onRecord(PWVideoResult(
                    fileURL: video.url,
                    category: selectedCategory,
                    duration: video.duration,
                    thumbnail: video.thumbnail,
                    source: .camera,
                    location: location,
                    capturedAt: capturedAt
                ))
            }
        case .failure(let error):
            handlers.onError(error as? PWCameraError
                             ?? .videoRecordingFailed(error.localizedDescription))
        }
    }

    /// Animates the `flying` thumbnail along the drop arc, then appends `commit`
    /// to the pile when it lands. If there's no thumbnail, just appends.
    private func performDrop(flying: UIImage?, commit item: CapturedVideoItem) {
        guard let flying else { recorded.append(item); HapticsManager.shared.success(); return }
        dropImage = flying
        dropProgress = 0
        // Linear timing preserves the arc/bounce curve baked into PWDropPath.
        withAnimation(.linear(duration: PWDropPath.duration)) { dropProgress = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + PWDropPath.duration) {
            recorded.append(item)
            HapticsManager.shared.success()
            dropImage = nil
            dropProgress = 0
        }
    }

    private func importVideos(_ assets: [PHAsset]) {
        Task {
            let directory = OutputDirectory.resolve(config.outputDirectory)

            // Collected so the batch callback can report the whole selection
            // once, alongside the per-item callbacks that fire as each lands.
            var imported: [PWVideoResult] = []

            for asset in assets {
                guard let item = await MediaImporter.importVideo(
                    asset, into: directory, maxFileSizeMB: config.maxFileSizeMB
                ) else {
                    // Reported rather than silently dropped. This matters more
                    // than for photos: maxFileSizeMB rejects oversized clips, so
                    // a host that picked five and got three needs to know a size
                    // limit was the reason.
                    handlers.onError(.videoRecordingFailed(
                        "Could not import a selected video — it may exceed the "
                        + "\(Int(config.maxFileSizeMB)) MB limit"
                    ))
                    continue
                }

                didRecordAny = true
                let thumb = await MediaImporter.thumbnail(for: item.url)
                recorded.append(CapturedVideoItem(
                    thumbnail: thumb, url: item.url,
                    category: selectedCategory, source: .gallery
                ))

                if config.savesToPhotoLibrary {
                    Task {
                        if await PhotoLibrarySaver.ensureAddPermission() {
                            PhotoLibrarySaver.save(videoURL: item.url)
                        }
                    }
                }

                let result = PWVideoResult(
                    fileURL: item.url,
                    category: selectedCategory,
                    duration: item.duration,
                    thumbnail: thumb,
                    source: .gallery,
                    // No location for imports — see the photo screen.
                    location: nil,
                    capturedAt: Date()
                )
                imported.append(result)
                handlers.onRecord(result)
            }

            // One call for the whole selection. Skipped when nothing imported,
            // so a fully failed batch doesn't look like a successful empty one.
            if !imported.isEmpty { handlers.onImport(imported) }
        }
    }
}

// MARK: - Record button

/// The circular record button: a red disc that morphs to a rounded square while
/// recording. Dimmed/disabled in portrait.
private struct RecordButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.6), lineWidth: 4)
                    .frame(width: 74, height: 74)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 30, style: .continuous)
                    .fill(Color.red)
                    .frame(width: isRecording ? 34 : 60,
                           height: isRecording ? 34 : 60)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
    }
}


// MARK: - Previews

// Two things the canvas cannot give us, both worth knowing before trusting what
// you see here:
//
//   • There is no camera, so the preview layer stays black. These show the
//     overlay chrome over it — top bar, timer, category control, record button.
//   • Orientation comes from CoreMotion, which reports nothing in the canvas, so
//     the monitor sits at its `.portrait` default and every preview renders the
//     portrait state with the rotate-to-landscape notice. The landscape
//     recording layout can only be seen on a device or in the demo app.

#Preview("Video screen — full chrome") {
    PWVideoScreen(
        config: PWVideoConfig(
            categories: [
                PWCategory(id: "DRIVING", title: "Driving"),
                PWCategory(id: "FUNCTIONAL", title: "Functional"),
                PWCategory(id: "ENGINE", title: "Engine")
            ],
            startingCategoryID: "DRIVING",
            maxDuration: 180,
            overlayLabel: "MO6759"
        ),
        handlers: PWVideoHandlers(onRecord: { _ in })
    )
}

#Preview("Video screen — no categories, no badge") {
    // The minimal configuration: with the category control and badge both gone,
    // the bottom controls have to hold their position rather than drifting down.
    PWVideoScreen(
        config: PWVideoConfig(),
        handlers: PWVideoHandlers(onRecord: { _ in })
    )
}

#Preview("Video screen — torch, gallery and ultra-wide off") {
    // Every optional top-bar control hidden, which is the layout most likely to
    // leave an awkward gap — and the one that regressed when the torch button
    // was hardware-gated rather than disabled.
    PWVideoScreen(
        config: PWVideoConfig(
            categories: [PWCategory("Driving"), PWCategory("Functional")],
            allowsTorch: false,
            allowsUltraWide: false,
            allowsGallery: false,
            overlayLabel: "MO6759"
        ),
        handlers: PWVideoHandlers(onRecord: { _ in })
    )
}
