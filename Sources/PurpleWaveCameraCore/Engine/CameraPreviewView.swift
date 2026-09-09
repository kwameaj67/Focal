//
//  CameraPreviewView.swift
//  PurpleWaveCameraCore
//
//  A SwiftUI bridge to `AVCaptureVideoPreviewLayer`. Using a UIView whose
//  backing layer *is* the preview layer (via `layerClass`) is the most
//  efficient, glitch-free way to render a live camera feed — the layer resizes
//  with the view automatically, no manual frame juggling required.
//

import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// UIKit view whose root layer is an `AVCaptureVideoPreviewLayer`.
package final class PreviewUIView: UIView {

    package override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    /// Convenience accessor for the strongly-typed backing layer.
    package var previewLayer: AVCaptureVideoPreviewLayer {
        // Safe: `layerClass` guarantees the type above.
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Attaches the capture session and fills the view while preserving aspect.
    package func configure(with session: AVCaptureSession) {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }
}

/// SwiftUI wrapper that displays a live preview of the given capture session.
package struct CameraPreviewView: UIViewRepresentable {

    package let session: AVCaptureSession

    /// Called when the user taps to focus. Provides both the normalized device
    /// point (already converted through the preview layer, ready to hand to
    /// `AVCaptureDevice.focusPointOfInterest`) and the raw touch point in view
    /// coordinates (so the screen can draw the focus square there).
    package var onTapToFocus: ((_ devicePoint: CGPoint, _ touchPoint: CGPoint) -> Void)?

    /// Called on pinch with the accumulated scale and gesture state so the
    /// engine can apply zoom.
    package var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?

    /// Called when a hardware volume button is pressed (iOS 17.2+). Wire this to
    /// the shutter to support volume-button capture. When `nil`, no capture-event
    /// interaction is installed and the volume buttons behave normally.
    package var onHardwareShutter: (() -> Void)?

    package init(
        session: AVCaptureSession,
        onTapToFocus: ((_ devicePoint: CGPoint, _ touchPoint: CGPoint) -> Void)? = nil,
        onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)? = nil,
        onHardwareShutter: (() -> Void)? = nil
    ) {
        self.session = session
        self.onTapToFocus = onTapToFocus
        self.onPinch = onPinch
        self.onHardwareShutter = onHardwareShutter
    }

    package func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.configure(with: session)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)

        // Capture the hardware volume buttons for the shutter. This is the only
        // App-Store-safe API for it and requires iOS 17.2+. We fire on `.ended`
        // so a single press takes one photo.
        if onHardwareShutter != nil, #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { [weak coordinator = context.coordinator] event in
                if event.phase == .ended { coordinator?.onHardwareShutter?() }
            }
            view.addInteraction(interaction)
        }

        return view
    }

    package func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Keep the coordinator's callbacks fresh across SwiftUI updates.
        context.coordinator.onTapToFocus = onTapToFocus
        context.coordinator.onPinch = onPinch
        context.coordinator.onHardwareShutter = onHardwareShutter
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator(onTapToFocus: onTapToFocus, onPinch: onPinch, onHardwareShutter: onHardwareShutter)
    }

    /// Routes UIKit gesture callbacks back into SwiftUI closures.
    package final class Coordinator: NSObject {
        var onTapToFocus: ((_ devicePoint: CGPoint, _ touchPoint: CGPoint) -> Void)?
        var onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?
        var onHardwareShutter: (() -> Void)?

        init(
            onTapToFocus: ((_ devicePoint: CGPoint, _ touchPoint: CGPoint) -> Void)?,
            onPinch: ((CGFloat, UIGestureRecognizer.State) -> Void)?,
            onHardwareShutter: (() -> Void)?
        ) {
            self.onTapToFocus = onTapToFocus
            self.onPinch = onPinch
            self.onHardwareShutter = onHardwareShutter
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewUIView else { return }
            let touchPoint = gesture.location(in: view)
            // Convert the tap through the preview layer so cropping from
            // `resizeAspectFill` is accounted for before we hand it to the
            // capture device.
            let devicePoint = view.previewLayer.captureDevicePointConverted(
                fromLayerPoint: touchPoint
            )
            onTapToFocus?(devicePoint, touchPoint)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            onPinch?(gesture.scale, gesture.state)
        }
    }
}
