//
//  RotateToLandscapeOverlay.swift
//  FocalVideo
//
//  Full-bleed overlay shown on the video recorder while the device is in
//  portrait and the recorder is configured landscape-only. Prompts the user to
//  rotate to landscape before recording.
//

import SwiftUI
import FocalCore

struct RotateToLandscapeOverlay: View {

    /// Optional handler for the "how to disable rotation lock" affordance. When
    /// `nil`, the help row is hidden.
    var onHelpTapped: (() -> Void)?

    var body: some View {
        // No full-bleed scrim and no hit testing: this is a notice, not a modal,
        // so the controls stay reachable while the user sets up before rotating.
        VStack {
            Spacer()

            VStack(spacing: 12) {
                Text("Please rotate your device to landscape to continue. "
                     + "If the screen does not rotate, Rotation Lock may be enabled.")
                    .font(FocalFont.rounded(17))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let onHelpTapped {
                    Button(action: onHelpTapped) {
                        Label("How to Disable Rotation Lock", systemImage: "info.circle")
                            .font(FocalFont.rounded(16))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.85))
            )
            .padding(.horizontal, 32)

            Spacer()
        }
        .allowsHitTesting(false)
    }
}
