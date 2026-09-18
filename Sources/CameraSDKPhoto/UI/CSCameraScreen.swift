//
//  CSCameraScreen.swift
//  CameraSDKPhoto
//
//  The public SwiftUI photo capture screen. A full camera layout: live
//  preview, flash menu, gallery import, ultra-wide toggle,
//  pinch-zoom, tap-to-focus, a category scroll bar, and a shutter that keeps the
//  screen open for multi-shot capture. Every capture is delivered through the
//  handlers passed in at construction.
//

import Photos
import SwiftUI
import Transmission
import CameraSDKCore

public struct CSCameraScreen: View {

    // MARK: Inputs

    private let config: CSCameraConfig
    private let handlers: CSPhotoHandlers

    // MARK: State

    @StateObject private var engine: PhotoCaptureEngine
    @StateObject private var orientation = DeviceOrientationMonitor()

    @State private var selectedCategory: CSCategory?
    @State private var showGallery = false
    @State private var focusPoint: CGPoint?
    /// All captures this session (camera + gallery), oldest → newest. Drives the
    /// stacked thumbnail pile and the full-screen gallery preview.
    @State private var captured: [CapturedPhotoItem] = []
    @State private var deniedPermission: CSPermission?
    @State private var didCaptureAny = false
    /// Guards one-time configuration so re-appearing (e.g. returning from the
    /// full-screen preview) doesn't re-configure the session.
    @State private var didSetUp = false

    // Drives the "photo drops into the thumbnail" animation after a capture.
    @State private var dropImage: UIImage?
    @State private var dropProgress: CGFloat = 0

    // Capture settings sheet.
    @State private var showSettings = false
    /// Whether the sheet was opened at the grid (via the gear) rather than
    /// deep-linked straight to one pane (via a rail icon). Governs whether a
    /// pane's back button returns to the grid or dismisses the sheet outright.
    @State private var settingsOpenedFromGrid = true
    @State private var settingsPane: CaptureSettingsPane = .grid
    @State private var aspectRatio: CSAspectRatio = .fourThree
    @State private var captureTimer: CSCaptureTimer = .off
    @State private var exposureBias: Float = 0
    /// Current capture frame rate, toggled from the rail.
    @State private var frameRate: CSFrameRate = .fps60
    /// Non-nil while the self-timer is counting down; drives the big countdown
    /// digit and blocks a second shutter press.
    @State private var countdown: Int?
    /// Whether the aspect/badge info tip is showing. Toggled by the info icon
    /// in the top bar.
    @State private var showInfoTip = false

    // MARK: Init

    /// Creates a photo capture screen.
    /// - Parameters:
    ///   - config: appearance/behaviour configuration.
    ///   - handlers: capture / finish / error callbacks.
    public init(config: CSCameraConfig, handlers: CSPhotoHandlers) {
        self.config = config
        self.handlers = handlers
        _engine = StateObject(wrappedValue: PhotoCaptureEngine(defaultFlashMode: config.defaultFlashMode))
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
                    handlers.onFinish(.cancelled)
                }
            } else {
                cameraLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        // Reads the live position of the thumbnail so the capture "drop"
        // animation knows where to land, then renders the flying image.
        .overlayPreferenceValue(ThumbnailAnchorKey.self) { anchor in
            dropOverlay(anchor: anchor)
        }
        .statusBarHidden(true)
        .task { await setUp() }
        // Resume the session when the screen re-appears (e.g. after dismissing
        // the full-screen preview), which is what un-freezes the live feed.
        .overlay {
            CaptureSettingsOverlay(isPresented: $showSettings) {
                settingsSheet
            }
        }
        .onAppear { if engine.isConfigured { engine.start(); orientation.start() } }
        .onDisappear { engine.stop(); orientation.stop() }
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
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous))
    }

    /// The chrome drawn on top of the preview: the top bar, zoom badge, and the
    /// shutter row.
    private var previewChrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 8)
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

    /// The image that arcs from the shutter into the thumbnail slot.
    private func dropOverlay(anchor: Anchor<CGRect>?) -> some View {
        DropFlightOverlay(image: dropImage, progress: dropProgress, anchor: anchor)
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
            onPinch: { scale, state in
                engine.setZoom(scale: scale, state: state)
            },
            // Hardware volume buttons act as the shutter (iOS 17.2+).
            onHardwareShutter: { capture() }
        )
        // Fills the ro unded card (the layer is `.resizeAspectFill`), so the
        // viewfinder is edge-to-edge with no letterboxing. The selected aspect
        // ratio still governs the captured file's crop, just not the preview.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let focusPoint { FocusSquare(point: focusPoint) }
        }
        .overlay {
            if let countdown {
                Text("\(countdown)")
                    .font(CameraSDKFont.rounded(96))
                    .foregroundColor(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
                    .id(countdown)
            }
        }
    }

    /// Slimmed to three icons — close, flash, settings — with the secondary
    /// tools moved to the right-edge rail.
    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            flashMenu
            Spacer()
            settingsButton
        }
        .padding(.horizontal, 15)
    }

    /// The top-left dismiss control. Finishes with whatever was captured this
    /// session, mirroring the old Cancel button.
    private var closeButton: some View {
        iconButton(systemName: "xmark") {
            handlers.onFinish(didCaptureAny ? .done : .cancelled)
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Tool rail

    /// The right-edge column of secondary tools, centred vertically.
    private var rail: some View {
        HStack {
            Spacer()
            CaptureToolRail(items: railItems, rotation: orientation.angle)
                .padding(.trailing, 14)
                // The info tip grows from just under the Info row (the last
                // item), its caret pointing back up at the icon.
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
            isActive: aspectRatio != .fourThree
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
    /// permanently over the viewfinder.
    private var infoTip: some View {
        InfoTip {
            VStack(alignment: .leading, spacing: 4) {
                Text(orientation.orientation.csIsLandscape ? "4:3 Landscape" : "3:4 Portrait")
                    .font(CameraSDKFont.rounded(14))
                    .foregroundColor(.white)

                if let label = config.overlayLabel {
                    Text(label)
                        .font(CameraSDKFont.rounded(13))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    /// The shutter, centred over the preview, with the captured-stack thumbnail
    /// trailing it. A `ZStack` keeps the shutter dead centre regardless of the
    /// thumbnail's size.
    private var shutterRow: some View {
        ZStack {
            ShutterButton(isEnabled: !engine.isProcessing) { capture() }

            HStack {
                Spacer()
                thumbnailPreviewLink
            }
            .padding(.trailing, 24)
        }
    }

    /// Gallery import shortcut, shown on the leading edge of the bottom bar in
    /// line with the categories. A fixed-size clear stand-in preserves the
    /// category centring when the host disables the gallery.
    @ViewBuilder
    private var galleryCorner: some View {
        if config.allowsGallery {
            iconButton(systemName: "photo.fill") {
                HapticsManager.shared.tap()
                openGallery()
            }
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// The stacked pile of recent captures. When there's at least one, tapping
    /// it presents the full-screen gallery preview via Transmission's zoom
    /// transition; the anchor reports its frame for the drop animation.
    @ViewBuilder
    private var thumbnailPreviewLink: some View {
        if captured.isEmpty {
            stackThumbnail
        } else {
            PresentationLink(transition: .zoomIfAvailable) {
                CapturedGalleryPreview(items: captured, startIndex: captured.count - 1)
            } label: {
                stackThumbnail
            }
            .buttonStyle(.plain)
        }
    }

    private var stackThumbnail: some View {
        CapturedStackThumbnail(images: captured.map(\.thumbnail))
            .thumbnailAnchor()
    }

    // MARK: - Capture settings

    private var settingsButton: some View {
        Button {
            HapticsManager.shared.tap()
            settingsPane = .grid          // always reopen at the root
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
        .accessibilityLabel("Capture settings")
    }

    /// Tiles shown at the root of the sheet. Each carries its current value so
    /// the grid doubles as a summary of the camera's state.
    private var settingsTiles: [CaptureSettingsTile] {
        var tiles: [CaptureSettingsTile] = [
            CaptureSettingsTile(
                id: "flash", pane: .flash, systemImage: flashIcon,
                title: "Flash",
                // Yellow only when forced on, matching the top-bar flash button
                // — auto is the default and shouldn't read as "changed".
                isActive: engine.flashMode == .on
            ),
            CaptureSettingsTile(
                id: "aspect", pane: .aspectRatio, systemImage: "aspectratio",
                title: "Aspect",
                // 4:3 is the sensor's native shape, so anything else is a
                // deliberate crop and worth flagging.
                isActive: aspectRatio != .fourThree
            ),
            CaptureSettingsTile(
                id: "timer", pane: .timer, systemImage: "timer",
                title: "Timer",
                isActive: captureTimer.isOn,
                // Once set, the delay itself is the useful thing to show.
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

    /// One sheet whose contents swap, rather than nested sheets — no
    /// presentation flicker when stepping between the grid and a control.
    @ViewBuilder
    private var settingsSheet: some View {
        switch settingsPane {
        case .grid:
            CaptureSettingsChrome() {
                CaptureSettingsGrid(tiles: settingsTiles) { pane in
                    withAnimation(CaptureSettingsOverlay<EmptyView>.motion) { settingsPane = pane }
                }
            }

        case .flash:
            CaptureSettingsChrome(title: "Flash", onBack: settingsBack) {
                DiscreteWheel(
                    values: [CSFlashMode.auto, .on, .off],
                    selection: Binding(
                        get: { engine.flashMode },
                        set: { engine.flashMode = $0 }
                    ),
                    title: { mode in
                        switch mode {
                        case .auto: return "Auto"
                        case .on:   return "On"
                        case .off:  return "Off"
                        }
                    }
                )
            }

        case .aspectRatio:
            CaptureSettingsChrome(title: "Aspect Ratio", onBack: settingsBack) {
                AspectRatioSelector(selection: $aspectRatio)
            }

        case .timer:
            CaptureSettingsChrome(title: "Timer", onBack: settingsBack) {
                DiscreteWheel(
                    values: CSCaptureTimer.allCases,
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
                        .font(CameraSDKFont.rounded(13))
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

    // MARK: - Flash menu

    private var flashMenu: some View {
        Menu {
            Button { engine.flashMode = .auto; HapticsManager.shared.selection() } label: { Label("Auto", systemImage: "bolt.badge.a") }
            Button { engine.flashMode = .on; HapticsManager.shared.selection() } label: { Label("On", systemImage: "bolt") }
            Button { engine.flashMode = .off; HapticsManager.shared.selection() } label: { Label("Off", systemImage: "bolt.slash") }
        } label: {
            Image(systemName: flashIcon)
                .font(.system(size: 20))
                .foregroundColor(engine.flashMode == .on ? .yellow : .white)
                .frame(width: 44, height: 44)
        }
    }

    private var flashIcon: String {
        switch engine.flashMode {
        case .auto: return "bolt.badge.a"
        case .on:   return "bolt"
        case .off:  return "bolt.slash"
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
            mediaType: .image,
            onDone: { assets in
                showGallery = false
                importImages(assets)
            },
            onCancel: { showGallery = false }
        )
    }

    // MARK: - Actions

    private func setUp() async {
        // `.task` re-runs on every appearance; only configure the session once.
        guard !didSetUp else { return }
        didSetUp = true

        // Bring the haptic engine up once, here in the guarded one-time setup —
        // NOT in the SwiftUI `init`, which runs on every view rebuild.
        HapticsManager.shared.setupHapticEngine()
        HapticsManager.shared.addObservers()

        // The preview canvas has no camera and nowhere to present a permission
        // prompt, so the requests below would leave the screen stuck on its
        // denied state. Stop here and let the chrome render over an empty
        // preview layer, which is what the canvas is useful for.
        guard !ProcessInfo.isRunningInXcodePreview else { return }

        // Ask up front rather than at first capture: prompting mid-shutter
        // would stall the capture behind a system dialog. A denial is not
        // fatal — captures just carry no location.
        if config.capturesLocation {
            await LocationManager.shared.requestAuthorization()
        }

        if let denied = await MediaPermissions.ensurePhotoPermissions() {
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
            handlers.onError(error as? CSCameraError
                             ?? .sessionConfigurationFailed(error.localizedDescription))
        }
    }

    private func capture() {
        // Ignore the shutter while a countdown is already running, so a second
        // tap (or a volume press) can't queue a second capture.
        guard countdown == nil else { return }
        HapticsManager.shared.tap()

        guard captureTimer.isOn else { return performCapture() }

        Task {
            for remaining in stride(from: captureTimer.rawValue, through: 1, by: -1) {
                withAnimation(.easeOut(duration: 0.15)) { countdown = remaining }
                HapticsManager.shared.tap()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            withAnimation { countdown = nil }
            performCapture()
        }
    }

    private func performCapture() {
        Task {
            do {
                let photo = try await engine.capturePhoto(orientation: orientation.orientation)
                didCaptureAny = true

                // The sensor delivers 4:3. For 16:9 and 1:1 the user framed the
                // shot in that ratio, so the file should match the viewfinder —
                // crop, and re-encode so `imageData` agrees with `image`.
                let image = ImageCropper.crop(photo.image, to: aspectRatio)
                let data = aspectRatio.croppedFromSensor
                    ? (ImageCropper.encode(image) ?? photo.data)
                    : photo.data

                let item = CapturedPhotoItem(data: data, image: image, category: selectedCategory)
                performDrop(flying: item.thumbnail, commit: item)

                // Fire and forget, so neither the save nor its permission
                // prompt sits between the shutter and onCapture.
                if config.savesToPhotoLibrary {
                    Task {
                        if await PhotoLibrarySaver.ensureAddPermission() {
                            PhotoLibrarySaver.save(imageData: data)
                        }
                    }
                }

                let location = config.capturesLocation
                    ? await LocationManager.shared.currentLocation()
                    : nil

                handlers.onCapture(CSPhotoResult(
                    imageData: data,
                    image: image,
                    category: selectedCategory,
                    source: .camera,
                    orientation: orientation.orientation,
                    metadata: photo.metadata,
                    location: location,
                    capturedAt: Date()
                ))
            } catch {
                handlers.onError(error as? CSCameraError
                                 ?? .photoCaptureFailed(error.localizedDescription))
            }
        }
    }

    /// Animates the `flying` thumbnail along the drop arc, then appends `commit`
    /// to the pile when it lands.
    private func performDrop(flying: UIImage, commit item: CapturedPhotoItem) {
        dropImage = flying
        dropProgress = 0
        // Linear timing preserves the arc/bounce curve baked into CSDropPath.
        withAnimation(.linear(duration: CSDropPath.duration)) { dropProgress = 1 }

        // When the flying image lands, add it to the pile, fire a success tick,
        // and clear the layer.
        DispatchQueue.main.asyncAfter(deadline: .now() + CSDropPath.duration) {
            captured.append(item)
            HapticsManager.shared.success()
            dropImage = nil
            dropProgress = 0
        }
    }

    private func importImages(_ assets: [PHAsset]) {
        Task {
            // Collected so the batch callback can report the whole selection
            // once, alongside the per-item callbacks that fire as each lands.
            //
            // These results decode lazily, so the array costs roughly the
            // encoded size of the selection rather than one full bitmap per
            // photo — the difference between ~120 MB and ~2 GB for forty.
            var imported: [CSPhotoResult] = []

            for asset in assets {
                // The decoded image is scoped to this iteration on purpose: it
                // is only here to derive a thumbnail, and holding one per asset
                // is exactly what used to exhaust memory on a large selection.
                guard let item = await MediaImporter.importImage(asset) else {
                    // An asset that can't be imported is reported rather than
                    // silently dropped — otherwise a host that picked ten and
                    // received eight has no way to know why.
                    handlers.onError(.photoCaptureFailed("Could not import a selected photo"))
                    continue
                }
                didCaptureAny = true
                captured.append(CapturedPhotoItem(data: item.data,
                                                  image: item.image,
                                                  category: selectedCategory))

                if config.savesToPhotoLibrary {
                    PhotoLibrarySaver.save(imageData: item.data)
                }

                let result = CSPhotoResult(
                    imageData: item.data,
                    category: selectedCategory,
                    source: .gallery,
                    orientation: orientation.orientation,
                    metadata: nil,
                    // No location for imports: the device's position now says
                    // nothing about where the asset was originally taken, and
                    // claiming otherwise would be worse than leaving it nil.
                    location: nil,
                    capturedAt: Date()
                )
                imported.append(result)
                handlers.onCapture(result)
            }

            // One call for the whole selection. Skipped when nothing imported,
            // so a fully failed batch doesn't look like a successful empty one.
            if !imported.isEmpty { handlers.onImport(imported) }
        }
    }
}

// MARK: - Shutter button

/// The circular shutter button (white ring with an inner disc).
private struct ShutterButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(Color.white).frame(width: 60, height: 60)
            }
        }
        .buttonStyle(.pressable(scale: 0.90))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Previews

// The canvas has no camera, so the preview layer stays black and these show the
// overlay chrome over it — the top bar, badges, category selector, shutter and
// settings sheet. That covers everything worth iterating on here; anything
// involving an actual frame needs the demo app on a device.

#Preview("Photo screen — full chrome") {
    CSCameraScreen(
        config: CSCameraConfig(
            categories: [
                CSCategory(id: "AMKT", title: "Profile"),
                CSCategory(id: "STICKER", title: "Sticker"),
                CSCategory(id: "WALKAROUND", title: "Walk Around")
            ],
            startingCategoryID: "AMKT",
            overlayLabel: "MO6759"
        ),
        handlers: CSPhotoHandlers(onCapture: { _ in })
    )
}

#Preview("Photo screen — no categories, no badge") {
    // The minimal configuration: with the category bar and badge both gone, the
    // bottom controls have to hold their position rather than drifting down.
    CSCameraScreen(
        config: CSCameraConfig(),
        handlers: CSPhotoHandlers(onCapture: { _ in })
    )
}

#Preview("Photo screen — gallery and ultra-wide off") {
    // Both optional top-bar controls hidden, which is the layout most likely to
    // leave an awkward gap.
    CSCameraScreen(
        config: CSCameraConfig(
            categories: [CSCategory("Profile"), CSCategory("Sticker")],
            allowsGallery: false,
            allowsUltraWide: false,
            overlayLabel: "MO6759"
        ),
        handlers: CSPhotoHandlers(onCapture: { _ in })
    )
}
