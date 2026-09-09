//
//  RotateToLandscapeOverlay.swift
//  PurpleWaveCameraVideo
//
//  Full-bleed overlay shown on the video recorder while the device is in
//  portrait. Mirrors FieldTool's `CenterOverlayView` prompt telling the user to
//  rotate to landscape before recording.
//

import SwiftUI
import PurpleWaveCameraCore

struct RotateToLandscapeOverlay: View {

    /// Optional handler for the "how to disable rotation lock" affordance. When
    /// `nil`, the help row is hidden.
    var onHelpTapped: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Please rotate your device to landscape to continue. "
                     + "If the screen does not rotate, Rotation Lock may be enabled.")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let onHelpTapped {
                    Button(action: onHelpTapped) {
                        Label("How to Disable Rotation Lock", systemImage: "info.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)
            )
            .padding(.horizontal, 32)
        }
    }
}
