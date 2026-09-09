//
//  CaptureSettingsSheet.swift
//  PurpleWaveCameraCore
//
//  The capture-settings sheet and its sub-overlays, shared by both screens.
//
//  Structure: one bottom sheet showing a grid of settings. Tapping a tile
//  swaps the sheet's contents for that setting's control, with a back arrow
//  returning to the grid. It's one sheet whose body changes rather than a
//  stack of sheets, so there's no presentation flicker between levels.
//

import SwiftUI

package extension Color {
    /// Background for the capture-settings sheet.
    ///
    /// A solid dark grey rather than `.ultraThinMaterial`: the sheet sits over a
    /// live camera feed, so a translucent material picked up whatever was in
    /// frame and the panel's tone shifted as the camera moved. Both the chrome
    /// and the sheet's `presentationBackground` use this, so the panel and the
    /// safe-area strip beneath it stay the same colour.
    static let pwSettingsSheet = Color(red: 0.11, green: 0.11, blue: 0.12)
}

// MARK: - Which pane the sheet is showing

/// The sheet's current level. `.grid` is the root; everything else is a
/// sub-overlay reached from it.
package enum CaptureSettingsPane: Equatable {
    case grid
    case flash
    case aspectRatio
    case timer
    case exposure
    case lens
}

/// One tile in the settings grid.
package struct CaptureSettingsTile: Identifiable {
    package let id: String
    package let pane: CaptureSettingsPane
    package let systemImage: String
    package let title: String

    /// `true` when the setting is doing something — flash on, a timer set, a
    /// non-zero exposure. Renders the glyph yellow, so the grid shows at a
    /// glance which settings are away from their defaults.
    package let isActive: Bool

    /// Replaces the glyph with this text when non-nil. The timer uses it to
    /// show "3s" instead of a clock face once it's set, which reads faster than
    /// an icon plus a separate value label.
    package let displayText: String?

    package init(
        id: String,
        pane: CaptureSettingsPane,
        systemImage: String,
        title: String,
        isActive: Bool = false,
        displayText: String? = nil
    ) {
        self.id = id
        self.pane = pane
        self.systemImage = systemImage
        self.title = title
        self.isActive = isActive
        self.displayText = displayText
    }
}

// MARK: - Chrome

/// Sheet chrome: a grabber, a title, and — below the root — a back arrow.
package struct CaptureSettingsChrome<Content: View>: View {

    private let title: String?
    private let onBack: (() -> Void)?
    private let content: Content

    /// - Parameter onBack: `nil` at the root, which hides the arrow.
    package init(
        title: String? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onBack = onBack
        self.content = content()
    }

    package var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let title = title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                if let onBack {
                    HStack {
                        Button {
                            HapticsManager.shared.tap()
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Back to settings")
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            content
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Root grid

/// The grid of settings tiles.
package struct CaptureSettingsGrid: View {

    private let tiles: [CaptureSettingsTile]
    private let onSelect: (CaptureSettingsPane) -> Void

    package init(
        tiles: [CaptureSettingsTile],
        onSelect: @escaping (CaptureSettingsPane) -> Void
    ) {
        self.tiles = tiles
        self.onSelect = onSelect
    }

    /// Three per row. Fixed rather than adaptive so the row count is
    /// predictable — the sheet's detent has to be sized for it, and an adaptive
    /// grid that reflows on a narrower device would leave the sheet the wrong
    /// height.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    package var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(tiles) { tile in
                Button {
                    HapticsManager.shared.selection()
                    onSelect(tile.pane)
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 54, height: 54)

                            if let text = tile.displayText {
                                Text(text)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            } else {
                                Image(systemName: tile.systemImage)
                                    .font(.system(size: 23, weight: .medium))
                            }
                        }
                        // Only the glyph carries the active state; the container
                        // stays neutral so the row doesn't turn into a wall of
                        // yellow when several settings are in use.
                        .foregroundColor(tile.isActive ? .yellow : .white)

                        Text(tile.title.uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .kerning(0.6)
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        // The root pane has no title bar, so without this the first row of
        // tiles crowds the grabber.
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - Aspect ratio selector

/// Horizontal single-select for aspect ratio, with a proportional preview of
/// each shape so the choice reads visually rather than only as a label.
package struct AspectRatioSelector: View {

    @Binding private var selection: PWAspectRatio

    package init(selection: Binding<PWAspectRatio>) {
        self._selection = selection
    }

    package var body: some View {
        HStack(spacing: 12) {
            ForEach(PWAspectRatio.allCases, id: \.self) { ratio in
                let isSelected = ratio == selection
                Button {
                    guard ratio != selection else { return }
                    HapticsManager.shared.selection()
                    withAnimation(.easeOut(duration: 0.18)) { selection = ratio }
                } label: {
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isSelected ? Color.yellow : Color.white.opacity(0.6),
                                    lineWidth: isSelected ? 2 : 1.2)
                            .aspectRatio(ratio.ratio(isLandscape: false), contentMode: .fit)
                            .frame(height: 34)

                        Text(ratio.title)
                            .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? .yellow : .white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Previews

/// The tiles the photo screen shows, with plausible values — previewing an
/// empty or placeholder grid would hide how the value labels wrap.
private let previewTiles: [CaptureSettingsTile] = [
    // A deliberately mixed row: two settings at their defaults and two active,
    // so the yellow-glyph treatment can be judged against its neighbours rather
    // than in isolation. The timer is set, so it shows "5s" in place of a glyph.
    CaptureSettingsTile(id: "flash", pane: .flash,
                        systemImage: "bolt", title: "Flash", isActive: true),
    CaptureSettingsTile(id: "aspect", pane: .aspectRatio,
                        systemImage: "aspectratio", title: "Aspect"),
    CaptureSettingsTile(id: "timer", pane: .timer,
                        systemImage: "timer", title: "Timer",
                        isActive: true, displayText: "5s"),
    CaptureSettingsTile(id: "exposure", pane: .exposure,
                        systemImage: "sun.max", title: "Exposure")
]

#Preview("Settings sheet — root grid") {
    ZStack(alignment: .bottom) {
        Color.black
        CaptureSettingsChrome() {
            CaptureSettingsGrid(tiles: previewTiles) { _ in }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8)
    }
    .ignoresSafeArea()
}

#Preview("Settings sheet — sub-overlay with back") {
    @Previewable @State var ratio: PWAspectRatio = .sixteenNine
    ZStack(alignment: .bottom) {
        Color.black
        CaptureSettingsChrome(title: "Aspect Ratio", onBack: {}) {
            AspectRatioSelector(selection: $ratio)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8)
    }
    .ignoresSafeArea()
}

#Preview("Aspect selector — each option") {
    @Previewable @State var ratio: PWAspectRatio = .fourThree
    ZStack {
        Color.black
        VStack(spacing: 24) {
            AspectRatioSelector(selection: $ratio)
            Text("Selected: \(ratio.title)")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    .ignoresSafeArea()
}

// MARK: - Overlay container

/// Bottom overlay that hosts the settings panes.
///
/// This deliberately isn't a `.sheet`. `presentationDetents` cannot interpolate
/// between heights — changing `.height(x)` rebuilds the detent set and the sheet
/// snaps, so a pane swap jumped rather than morphed. As an ordinary view the
/// panel's height is just a layout property, which SwiftUI animates for free.
///
/// What a system sheet gave us that this re-implements: drag-to-dismiss and a
/// tap-outside target. What it gave us that we were overriding anyway: the
/// background, the drag indicator, and a fixed height.
package struct CaptureSettingsOverlay<Content: View>: View {

    @Binding private var isPresented: Bool
    private let content: Content

    /// Live drag translation while the panel is being pulled down.
    @State private var dragOffset: CGFloat = 0

    package init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.content = content()
    }

    /// Shared curve for presentation, dismissal and height changes, so a pane
    /// swap that also resizes reads as one motion rather than two.
    package static var motion: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    package var body: some View {
        ZStack(alignment: .bottom) {
            // Tap-outside target. Nearly transparent rather than a visible
            // scrim: this sits over a live viewfinder, and dimming the frame
            // the user is composing would be worse than leaving it clear.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            panel
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 2)

            content
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.pwSettingsSheet)
                // Extends under the home indicator so the panel meets the
                // screen edge instead of floating above it.
                .ignoresSafeArea(edges: .bottom)
        )
        .offset(y: dragOffset)
        .gesture(dragToDismiss)
        .environment(\.colorScheme, .dark)
    }

    private var dragToDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                // Downward only; dragging up shouldn't stretch the panel.
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                // Honour a fast flick as well as a long pull, so a quick
                // downward swipe dismisses without travelling the full distance.
                let flicked = value.predictedEndTranslation.height > 140
                if value.translation.height > 70 || flicked {
                    dismiss()
                } else {
                    withAnimation(Self.motion) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        HapticsManager.shared.tap()
        withAnimation(Self.motion) {
            isPresented = false
            dragOffset = 0
        }
    }
}
