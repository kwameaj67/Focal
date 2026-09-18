//
//  CaptureToolRail.swift
//  CameraSDKCore
//
//  The vertical rail of secondary tools pinned to the right edge of the capture
//  screens, centred vertically. Each row is a label followed by a round icon
//  button (label on the left, icon on the right), so the whole column reads as a
//  right-aligned list — the layout the photo and video screens share.
//
//  Purely presentational: the caller supplies the items and their actions, so
//  the same rail serves both screens without knowing anything about the engine.
//

import SwiftUI

/// One row in a `CaptureToolRail`.
package struct CaptureToolRailItem: Identifiable {
    package let id: String
    package let title: String
    package let systemImage: String
    /// Tints the row yellow when the tool is engaged (e.g. the timer is set),
    /// matching the highlight the top-bar controls use.
    package let isActive: Bool
    package let action: () -> Void

    package init(
        id: String,
        title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }
}

/// A right-aligned vertical stack of labelled tool buttons.
package struct CaptureToolRail: View {

    package let items: [CaptureToolRailItem]
    /// Rotation applied to each row so labels and icons stay upright as the
    /// device rotates, matching the other on-screen controls.
    package var rotation: Double

    package init(items: [CaptureToolRailItem], rotation: Double = 0) {
        self.items = items
        self.rotation = rotation
    }

    package var body: some View {
        VStack(alignment: .trailing, spacing: 20) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 10) {
                        Text(item.title)
                            .font(CameraSDKFont.rounded(14))
                        Image(systemName: item.systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color.black.opacity(0.28)))
                    }
                    .foregroundColor(item.isActive ? .yellow : .white)
                }
                .buttonStyle(.pressable(scale: 0.95))
                .accessibilityLabel(item.title)
            }
        }
    }
}

// MARK: - Previews

#Preview("Tool rail") {
    ZStack {
        Color.black
        HStack {
            Spacer()
            CaptureToolRail(items: [
                CaptureToolRailItem(id: "lens", title: "Lens", systemImage: "camera") {},
                CaptureToolRailItem(id: "timer", title: "Timer", systemImage: "timer", isActive: true) {},
                CaptureToolRailItem(id: "aspect", title: "Aspect", systemImage: "aspectratio") {},
                CaptureToolRailItem(id: "info", title: "Info", systemImage: "info.circle") {}
            ])
            .padding(.trailing, 14)
        }
    }
    .ignoresSafeArea()
}
