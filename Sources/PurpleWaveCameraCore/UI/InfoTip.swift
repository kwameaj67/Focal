//
//  InfoTip.swift
//  PurpleWaveCameraCore
//
//  A small callout that animates out from under the control that toggled it.
//
//  Used for information the user occasionally wants to confirm — the current
//  aspect framing, the item badge — but which doesn't earn permanent space on
//  a viewfinder. Keeping it behind a toggle leaves the frame clear.
//

import SwiftUI

/// A caret-topped callout, sized to its content.
///
/// Positioned by the caller — it draws the bubble and the caret, and knows
/// nothing about where the triggering control is.
package struct InfoTip<Content: View>: View {

    /// How far in from the tip's trailing edge the caret points. Matches the
    /// centre of a 44pt control sitting above the tip's right edge.
    private let caretInset: CGFloat = 22

    private let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Caret()
                .fill(Color.pwSettingsSheet)
                .frame(width: 14, height: 7)
                .padding(.trailing, caretInset)

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.pwSettingsSheet)
                )
        }
        .environment(\.colorScheme, .dark)
        // Grows from the caret rather than the centre, so it reads as coming
        // out of the button that opened it.
        .transition(
            .scale(scale: 0.85, anchor: .topTrailing)
            .combined(with: .opacity)
        )
    }
}

/// The upward triangle joining the bubble to its control.
private struct Caret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Info tip") {
    ZStack(alignment: .topTrailing) {
        Color.black
        InfoTip {
            VStack(alignment: .leading, spacing: 4) {
                Text("3:4 Portrait")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("MO6759")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.top, 60)
        .padding(.trailing, 16)
    }
    .ignoresSafeArea()
}
