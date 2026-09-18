//
//  FCVideoScreen.swift
//  FocalVideo
//
//  The public SwiftUI video recorder: live
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
import FocalCore

public struct FCVideoScreen: View {

    // MARK: Inputs

    private let config: FCVideoConfig
    private let handlers: FCVideoHandlers

    // MARK: State

    @StateObject private var engine: VideoRecordEngine
    @StateObject private var orientation = DeviceOrientationMonitor()

    /// Dismisses the screen when presented via `.sheet` / `.fullScreenCover`, so
    /// finishing dismisses the recorder even if the host's `onFinish` doesn't.
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: FCCategory?
    @State private var showGallery = false
    @State private var focusPoint: CGPoint?
    @State private var deniedPermission: FCPermission?
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
    /// Whether the sheet was opened at the grid (via the gear) rather than
    /// deep-linked straight to one pane (via a rail icon). Governs whether a
    /// pane's back button returns to the grid or dismisses the sheet outright.
    @State private var settingsOpenedFromGrid = true
    @State private var settingsPane: CaptureSettingsPane = .grid
    @State private var aspectRatio: FCAspectRatio = .sixteenNine
    @State private var captureTimer: FCCaptureTimer = .off
    @State private var exposureBias: Float = 0
    /// Current capture frame rate, toggled from the rail.
    @State private var frameRate: FCFrameRate = .fps60
    /// Non-nil while the self-timer counts down before recording starts.
    @State private var countdown: Int?
    /// Whether the aspect/badge info tip is showing. Toggled by the info icon
    /// in the top bar.
    @State private var showInfoTip = false

    // MARK: Init

    /// Creates a video recorder screen.
    public init(config: FCVideoConfig, handlers: FCVideoHandlers) {
        self.config = config
        self.handlers = handlers
        let dir = OutputDirectory.resolve(config.outputDirectory)
        _engine = StateObject(wrappedValue: VideoRecordEngine(
            defaultPreset: config.preset(for: config.initialCategory).avPreset,
            outputDirectory: dir
        ))
        _selectedCategory = State(initialValue: config.initialCategory)
        _frameRate = State(initialValue: config.defaultFrameRate)
    }

    // MARK: Body

    public var body: some View {
        // GeometryReader captures the safe-area insets up front so the preview
        // card can run edge-to-edge (under the notch) while the chrome inside it
        // still clears the notch and home indicator.
        Group {
            if let deniedPermission {
                PermissionDeniedView(permission: deniedPermission) {
                    finish(.cancelled)
                }
            } else {
                cameraLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
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

    // MARK: - Layout

    /// The rounded preview card, with the capture chrome layered over it, above a
    /// black bar that holds only the gallery button and category selector. The
    /// card sits within the safe area with a little extra top and bottom padding
    /// so it reads as a floating card on black.
    private var cameraLayout: some View {
        VStack(spacing: 0) {
            previewCard
            bottomBar
        }
        .padding(.top, Self.edgePadding)
        .padding(.bottom, Self.edgePadding)
    }

    private var previewCard: some View {
        ZStack {
            Color.black
            preview
            previewChrome
            rail

            // Portrait guard, only when the host restricts recording to
            // landscape: block until the device is rotated.
            if config.landscapeOnly && !orientation.orientation.fcIsLandscape {
                RotateToLandscapeOverlay(onHelpTapped: nil)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous))
    }

    /// Whether the current device orientation permits recording. Always `true`
    /// unless the host set `landscapeOnly`, in which case recording waits for
    /// landscape.
    private var orientationAllowsRecording: Bool {
        !config.landscapeOnly || orientation.orientation.fcIsLandscape
    }

    /// The chrome drawn on top of the preview: the top bar, timer pill, zoom
    /// badge, and the record row.
    private var previewChrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 8)
            timerPill
            Spacer()
            ZoomBadge(text: engine.zoomText, rotation: orientation.angle)
                .padding(.bottom, 8)
            shutterRow
                .padding(.bottom, 18)
        }
    }

    /// The strip below the preview: gallery on the leading edge, category
    /// selector centred across the full width.
    private var bottomBar: some View {
        ZStack {
            if !config.categories.isEmpty {
                CategoryScrollBar(
                    categories: config.categories,
                    selected: $selectedCategory,
                    rotation: orientation.angle
                )
                .disabled(engine.isRecording)
                // Fade the leading edge so pills dissolve as they scroll under
                // the gallery icon, which stays drawn on top.
                .mask(Self.categoryLeadingFade)
            }
            HStack {
                galleryCorner
                Spacer()
            }
            .padding(.leading, 16)
        }
        .padding(.top, 12)
    }

    /// A left-edge fade: transparent at the leading edge, solid after ~18%.
    private static var categoryLeadingFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Corner radius of the preview card.
    private static let previewCornerRadius: CGFloat = 28
    /// Extra breathing room above and below the card/bar.
    private static let edgePadding: CGFloat = 10

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
        // Fills the rounded card (the layer is `.resizeAspectFill`), so the
        // viewfinder is edge-to-edge with no letterboxing.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let focusPoint { FocusSquare(point: focusPoint) }
        }
        .overlay {
            if let countdown {
                Text("\(countdown)")
                    .font(FocalFont.rounded(96))
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
            settingsOpenedFromGrid = true
            withAnimation(CaptureSettingsOverlay<EmptyView>.motion) { showSettings = true }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.black.opacity(0.3)))
        }
        .buttonStyle(.pressable(scale: 0.95))
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
            CaptureSettingsChrome(title: "Torch", onBack: settingsBack) {
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
            CaptureSettingsChrome(title: "Aspect Ratio", onBack: settingsBack) {
                AspectRatioSelector(selection: $aspectRatio)
            }

        case .timer:
            CaptureSettingsChrome(title: "Timer", onBack: settingsBack) {
                DiscreteWheel(
                    values: FCCaptureTimer.allCases,
                    selection: $captureTimer,
                    title: \.title
                )
            }

        case .lens:
            CaptureSettingsChrome(title: "Lens", onBack: settingsBack) {
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
            CaptureSettingsChrome(title: "Exposure", onBack: settingsBack) {
                if let range = engine.exposureBiasRange {
                    ExposureWheel(value: $exposureBias, range: range)
                        .onChange(of: exposureBias) { _, bias in
                            engine.setExposureBias(bias)
                        }
                } else {
                    Text("Exposure adjustment is unavailable on this device.")
                        .font(FocalFont.rounded(13))
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                }
            }
        }
    }

    /// A pane's back button: return to the grid if the sheet was opened there,
    /// otherwise dismiss the sheet — a rail icon deep-links to a single pane, so
    /// backing out of it shouldn't surface a grid the user never opened.
    private func settingsBack() {
        withAnimation(CaptureSettingsOverlay<EmptyView>.motion) {
            if settingsOpenedFromGrid {
                settingsPane = .grid
            } else {
                showSettings = false
            }
        }
    }

    // MARK: - Overlays

    /// Slimmed to three icons — close, torch, settings — with the secondary
    /// tools moved to the right-edge rail. Torch stands in for the photo
    /// screen's flash here.
    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            if config.allowsTorch {
                iconButton(
                    systemName: engine.isTorchOn ? "bolt.fill" : "bolt.slash",
                    tint: engine.isTorchOn ? .yellow : .white
                ) { engine.toggleTorch(); HapticsManager.shared.tap() }
                    .disabled(!engine.hasTorch)
                    .opacity(engine.hasTorch ? 1 : 0.4)
            }
            Spacer()
            settingsButton
        }
        .padding(.horizontal, 20)
    }

    /// The top-left dismiss control. Finishes with whatever was recorded this
    /// session, mirroring the old Cancel button, and is blocked mid-take.
    private var closeButton: some View {
        iconButton(systemName: "xmark") {
            finish(didRecordAny ? .done : .cancelled)
        }
        .disabled(engine.isRecording)
        .accessibilityLabel("Close")
    }

    /// Notifies the host via `onFinish` and dismisses the screen. The `dismiss()`
    /// handles the common `.sheet` / `.fullScreenCover` presentation; it's a
    /// no-op under the UIKit factory, which dismisses its own controller.
    private func finish(_ reason: FCFinishReason) {
        handlers.onFinish(reason)
        dismiss()
    }

    // MARK: - Tool rail

    /// The right-edge column of secondary tools, centred vertically.
    private var rail: some View {
        HStack {
            Spacer()
            CaptureToolRail(items: railItems, rotation: orientation.angle)
                .padding(.trailing, 14)
                // The rail's tools reconfigure the session, so lock it while
                // recording — matching the other disabled record-time controls.
                .disabled(engine.isRecording)
                .overlay(alignment: .bottomTrailing) {
                    if showInfoTip {
                        infoTip
                            .fixedSize()
                            .offset(y: 72)
                            .padding(.trailing, 4)
                    }
                }
        }
    }

    private var railItems: [CaptureToolRailItem] {
        var items: [CaptureToolRailItem] = []
        if config.allowsUltraWide && engine.supportsUltraWide {
            items.append(CaptureToolRailItem(
                id: "lens", title: "Lens",
                systemImage: engine.isUltraWide ? "camera.aperture" : "camera",
                isActive: engine.isUltraWide
            ) { engine.toggleUltraWide(); HapticsManager.shared.impact() })
        }
        items.append(CaptureToolRailItem(
            id: "timer", title: "Timer", systemImage: "timer",
            isActive: captureTimer.isOn
        ) { openSettings(.timer) })
        items.append(CaptureToolRailItem(
            id: "aspect", title: "Aspect", systemImage: "aspectratio",
            isActive: aspectRatio != .sixteenNine
        ) { openSettings(.aspectRatio) })
        items.append(CaptureToolRailItem(
            id: "exposure", title: "Exposure", systemImage: "sun.max",
            isActive: exposureBias != 0
        ) { openSettings(.exposure) })
        items.append(CaptureToolRailItem(
            id: "fps", title: frameRate.title, systemImage: "speedometer",
            isActive: frameRate == .fps60
        ) { toggleFrameRate() })
        items.append(CaptureToolRailItem(
            id: "info", title: "Info",
            systemImage: showInfoTip ? "info.circle.fill" : "info.circle",
            isActive: showInfoTip
        ) {
            HapticsManager.shared.tap()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                showInfoTip.toggle()
            }
        })
        return items
    }

    /// Opens the settings sheet straight to one pane, used by the rail shortcuts.
    private func openSettings(_ pane: CaptureSettingsPane) {
        HapticsManager.shared.tap()
        settingsPane = pane
        settingsOpenedFromGrid = false
        withAnimation(CaptureSettingsOverlay<EmptyView>.motion) { showSettings = true }
    }

    /// Flips between 60 and 30 fps and applies it to the session.
    private func toggleFrameRate() {
        HapticsManager.shared.tap()
        frameRate = frameRate.toggled
        engine.setFrameRate(frameRate.rawValue)
    }

    /// Aspect framing and the item badge, shown on demand rather than parked
    /// permanently over the viewfinder — matching the photo screen.
    private var infoTip: some View {
        InfoTip {
            VStack(alignment: .leading, spacing: 4) {
                Text(aspectRatio.title)
                    .font(FocalFont.rounded(14))
                    .foregroundColor(.white)

                if let label = config.overlayLabel {
                    Text(label)
                        .font(FocalFont.rounded(13))
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
            .font(FocalFont.rounded(15))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(timerBackground)
            .cornerRadius(5)
            .padding(.top, 8)
    }

    /// The record button, centred over the preview, with the captured-stack
    /// thumbnail trailing it. A `ZStack` keeps the record button dead centre
    /// regardless of the thumbnail's size.
    private var shutterRow: some View {
        ZStack {
            RecordButton(isRecording: engine.isRecording,
                         isEnabled: orientationAllowsRecording && !engine.isBusy) {
                toggleRecording()
            }

            HStack {
                Spacer()
                thumbnailPreviewLink
            }
            .padding(.trailing, 24)
        }
    }

    /// Gallery import shortcut, shown on the leading edge of the bottom bar in
    /// line with the categories; blocked mid-take. A fixed-size clear stand-in
    /// preserves the category centring when the gallery is unavailable.
    @ViewBuilder
    private var galleryCorner: some View {
        if config.allowsGallery {
            iconButton(systemName: "photo.on.rectangle") {
                HapticsManager.shared.tap()
                openGallery()
            }
            .disabled(engine.isRecording)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
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

    /// The timer pill changes colour each minute (green → yellow → red).
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
        .buttonStyle(.pressable(scale: 0.95))
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
            engine.setFrameRate(frameRate.rawValue)
            orientation.start()
        } catch {
            handlers.onError(error as? FCCameraError
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
           orientationAllowsRecording, !engine.isBusy {
            HapticsManager.shared.impact()
            Task {
                for remaining in stride(from: captureTimer.rawValue, through: 1, by: -1) {
                    withAnimation(.easeOut(duration: 0.15)) { countdown = remaining }
                    HapticsManager.shared.tap()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                withAnimation { countdown = nil }
                // Re-check: the device may have been rotated out of a permitted
                // orientation during the countdown.
                if orientationAllowsRecording, !engine.isBusy {
                    engine.startRecording(orientation: orientation.orientation)
                }
            }
            return
        }

        if engine.isRecording {
            engine.stopRecording()
            HapticsManager.shared.impact()
        } else if orientationAllowsRecording && !engine.isBusy {
            // Mirrors the record button being disabled when the orientation
            // isn't permitted, so the volume-button path can't start a clip the
            // UI wouldn't allow.
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

                handlers.onRecord(FCVideoResult(
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
            handlers.onError(error as? FCCameraError
                             ?? .videoRecordingFailed(error.localizedDescription))
        }
    }

    /// Animates the `flying` thumbnail along the drop arc, then appends `commit`
    /// to the pile when it lands. If there's no thumbnail, just appends.
    private func performDrop(flying: UIImage?, commit item: CapturedVideoItem) {
        guard let flying else { recorded.append(item); HapticsManager.shared.success(); return }
        dropImage = flying
        dropProgress = 0
        // Linear timing preserves the arc/bounce curve baked into FCDropPath.
        withAnimation(.linear(duration: FCDropPath.duration)) { dropProgress = 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + FCDropPath.duration) {
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
            var imported: [FCVideoResult] = []

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

                let result = FCVideoResult(
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
        .buttonStyle(.pressable(scale: 0.90))
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
    FCVideoScreen(
        config: FCVideoConfig(
            categories: [
                FCCategory(id: "DRIVING", title: "Driving"),
                FCCategory(id: "FUNCTIONAL", title: "Functional"),
                FCCategory(id: "ENGINE", title: "Engine")
            ],
            startingCategoryID: "DRIVING",
            maxDuration: 180,
            overlayLabel: "MO6759"
        ),
        handlers: FCVideoHandlers(onRecord: { _ in })
    )
}

#Preview("Video screen — no categories, no badge") {
    // The minimal configuration: with the category control and badge both gone,
    // the bottom controls have to hold their position rather than drifting down.
    FCVideoScreen(
        config: FCVideoConfig(),
        handlers: FCVideoHandlers(onRecord: { _ in })
    )
}

#Preview("Video screen — torch, gallery and ultra-wide off") {
    // Every optional top-bar control hidden, which is the layout most likely to
    // leave an awkward gap — and the one that regressed when the torch button
    // was hardware-gated rather than disabled.
    FCVideoScreen(
        config: FCVideoConfig(
            categories: [FCCategory("Driving"), FCCategory("Functional")],
            allowsTorch: false,
            allowsUltraWide: false,
            allowsGallery: false,
            overlayLabel: "MO6759"
        ),
        handlers: FCVideoHandlers(onRecord: { _ in })
    )
}
