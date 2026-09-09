//
//  PWCameraScreen.swift
//  PurpleWaveCameraPhoto
//
//  The public SwiftUI photo capture screen. Rebuilds the FieldTool enhanced
//  camera layout: live preview, flash menu, gallery import, ultra-wide toggle,
//  pinch-zoom, tap-to-focus, a category scroll bar, and a shutter that keeps the
//  screen open for multi-shot capture. Every capture is delivered through the
//  handlers passed in at construction.
//

import Photos
import SwiftUI
import Transmission
import PurpleWaveCameraCore

public struct PWCameraScreen: View {

    // MARK: Inputs

    private let config: PWCameraConfig
    private let handlers: PWPhotoHandlers

    // MARK: State

    @StateObject private var engine: PhotoCaptureEngine
    @StateObject private var orientation = DeviceOrientationMonitor()

    @State private var selectedCategory: PWCategory?
    @State private var showGallery = false
    @State private var focusPoint: CGPoint?
    /// All captures this session (camera + gallery), oldest → newest. Drives the
    /// stacked thumbnail pile and the full-screen gallery preview.
    @State private var captured: [CapturedPhotoItem] = []
    @State private var deniedPermission: PWPermission?
    @State private var didCaptureAny = false
    /// Guards one-time configuration so re-appearing (e.g. returning from the
    /// full-screen preview) doesn't re-configure the session.
    @State private var didSetUp = false

    // Drives the "photo drops into the thumbnail" animation after a capture.
    @State private var dropImage: UIImage?
    @State private var dropProgress: CGFloat = 0

    // Capture settings sheet.
    @State private var showSettings = false
    @State private var settingsPane: CaptureSettingsPane = .grid
    @State private var aspectRatio: PWAspectRatio = .fourThree
    @State private var captureTimer: PWCaptureTimer = .off
    @State private var exposureBias: Float = 0
    /// Non-nil while the self-timer is counting down; drives the big countdown
    /// digit and blocks a second shutter press.
    @State private var countdown: Int?

    // MARK: Init

    /// Creates a photo capture screen.
    /// - Parameters:
    ///   - config: appearance/behaviour configuration.
    ///   - handlers: capture / finish / error callbacks.
    public init(config: PWCameraConfig, handlers: PWPhotoHandlers) {
        self.config = config
        self.handlers = handlers
        _engine = StateObject(wrappedValue: PhotoCaptureEngine(defaultFlashMode: config.defaultFlashMode))
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
            }
        }
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
            if showSettings {
                CaptureSettingsOverlay(isPresented: $showSettings) {
                    settingsSheet
                }
                .transition(.move(edge: .bottom))
            }
        }
        .onAppear { if engine.isConfigured { engine.start(); orientation.start() } }
        .onDisappear { engine.stop(); orientation.stop() }
        .sheet(isPresented: $showGallery) {
        }
    }

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

    // MARK: - Overlays

    private var overlays: some View {
        VStack(spacing: 0) {
            topBar
            aspectAndBadge
            Spacer()
            ZoomBadge(text: engine.zoomText, rotation: orientation.angle)
            .padding(.bottom, 8)
            if !config.categories.isEmpty {
                CategoryScrollBar(
                    categories: config.categories,
                    selected: $selectedCategory
                )
            }
            bottomControls
        }
        .padding(.vertical, 12)
    }

    private var topBar: some View {
        HStack {
            flashMenu
            Spacer()
            if config.allowsUltraWide && engine.supportsUltraWide {
                iconButton(
                    systemName: "camera.on.rectangle.fill",
                    tint: engine.isUltraWide ? .yellow : .white
                ) { engine.toggleUltraWide(); HapticsManager.shared.impact() }
            }
            if config.allowsGallery {
                iconButton(systemName: "photo.fill") {
                    HapticsManager.shared.tap()
                    showGallery = true
                }
            }
            settingsButton
        }
        .padding(.horizontal, 15)
    }

    private var aspectAndBadge: some View {
        HStack {
            Text(orientation.orientation.pwIsLandscape ? "4:3 Landscape" : "3:4 Portrait")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
                .cornerRadius(5)
            Spacer()
            if let label = config.overlayLabel {
                IcnBadge(icn: label)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        HStack {
            Button("Cancel") {
                handlers.onFinish(didCaptureAny ? .done : .cancelled)
            }
            .font(.system(size: 17))
            .foregroundColor(.white)
            .rotationEffect(.radians(orientation.angle))

            Spacer()

            ShutterButton(isEnabled: !engine.isProcessing) { capture() }

            Spacer()

            thumbnailPreviewLink
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
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
        CapturedStackThumbnail(images: captured.map(\.image))
            .rotationEffect(.radians(orientation.angle))
            .thumbnailAnchor()
    }

    // MARK: - Capture settings

    private var settingsButton: some View {
        Button {
            HapticsManager.shared.tap()
            settingsPane = .grid    
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.black.opacity(0.3)))
                .rotationEffect(.radians(orientation.angle))
        }
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
            CaptureSettingsChrome(title: "Flash", onBack: backToGrid) {
                DiscreteWheel(
                    values: [PWFlashMode.auto, .on, .off],
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
                .rotationEffect(.radians(orientation.angle))
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
                .rotationEffect(.radians(orientation.angle))
        }
    }

    // MARK: - Gallery

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

        let needsLibrary = config.allowsGallery || config.savesToPhotoLibrary
        if let denied = await MediaPermissions.ensurePhotoPermissions(needsLibrary: needsLibrary) {
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

                let item = CapturedPhotoItem(image: image, category: selectedCategory)
                let flying = image.preparingThumbnail(of: CGSize(width: 200, height: 200))
                performDrop(flying: flying, commit: item)

                if config.savesToPhotoLibrary {
                    PhotoLibrarySaver.save(imageData: data)
                }

                let location = config.capturesLocation
                    ? await LocationManager.shared.currentLocation()
                    : nil

                handlers.onCapture(PWPhotoResult(
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
                handlers.onError(error as? PWCameraError
                                 ?? .photoCaptureFailed(error.localizedDescription))
            }
        }
    }

    /// Animates the `flying` thumbnail along the drop arc, then appends `commit`
    /// to the pile when it lands.
    private func performDrop(flying: UIImage?, commit item: CapturedPhotoItem) {
        guard let flying else { captured.append(item); HapticsManager.shared.success(); return }
        dropImage = flying
        dropProgress = 0
        // Linear timing preserves the arc/bounce curve baked into PWDropPath.
        withAnimation(.linear(duration: PWDropPath.duration)) { dropProgress = 1 }

        // When the flying image lands, add it to the pile, fire a success tick,
        // and clear the layer.
        DispatchQueue.main.asyncAfter(deadline: .now() + PWDropPath.duration) {
            captured.append(item)
            HapticsManager.shared.success()
            dropImage = nil
            dropProgress = 0
        }
    }

    private func importImages(_ assets: [PHAsset]) {
        Task {
            for asset in assets {
                guard let imported = await MediaImporter.importImage(asset) else { continue }
                didCaptureAny = true
                captured.append(CapturedPhotoItem(image: imported.image, category: selectedCategory))

                if config.savesToPhotoLibrary {
                    PhotoLibrarySaver.save(imageData: imported.data)
                }

                handlers.onCapture(PWPhotoResult(
                    imageData: imported.data,
                    image: imported.image,
                    category: selectedCategory,
                    source: .gallery,
                    orientation: orientation.orientation,
                    metadata: nil,
                    // No location for imports: the device's position now says
                    // nothing about where the asset was originally taken, and
                    // claiming otherwise would be worse than leaving it nil.
                    location: nil,
                    capturedAt: Date()
                ))
            }
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
    PWCameraScreen(
        config: PWCameraConfig(
            categories: [
                PWCategory(id: "AMKT", title: "Profile"),
                PWCategory(id: "STICKER", title: "Sticker"),
                PWCategory(id: "WALKAROUND", title: "Walk Around")
            ],
            startingCategoryID: "AMKT",
            overlayLabel: "MO6759"
        ),
        handlers: PWPhotoHandlers(onCapture: { _ in })
    )
}

#Preview("Photo screen — no categories, no badge") {
    // The minimal configuration: with the category bar and badge both gone, the
    // bottom controls have to hold their position rather than drifting down.
    PWCameraScreen(
        config: PWCameraConfig(),
        handlers: PWPhotoHandlers(onCapture: { _ in })
    )
}

#Preview("Photo screen — gallery and ultra-wide off") {
    // Both optional top-bar controls hidden, which is the layout most likely to
    // leave an awkward gap.
    PWCameraScreen(
        config: PWCameraConfig(
            categories: [PWCategory("Profile"), PWCategory("Sticker")],
            allowsGallery: false,
            allowsUltraWide: false,
            overlayLabel: "MO6759"
        ),
        handlers: PWPhotoHandlers(onCapture: { _ in })
    )
}
