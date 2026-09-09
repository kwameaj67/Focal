//
//  PWCamera+Photo.swift
//  PurpleWaveCameraPhoto
//
//  UIKit entry point for photo capture.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (SwiftUI)
//  ─────────────────────────────────────────────────────────────────────────
//      PWCameraScreen(
//          config: PWCameraConfig(categories: [PWCategory("Profile")]),
//          handlers: PWPhotoHandlers(onCapture: { result in
//              // persist result.imageData / result.image
//          })
//      )
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (UIKit)
//  ─────────────────────────────────────────────────────────────────────────
//      let vc = PWCamera.makePhotoCapture(
//          config: PWCameraConfig(categories: [PWCategory("Profile")]),
//          handlers: PWPhotoHandlers(onCapture: { result in ... })
//      )
//      present(vc, animated: true)
//
//  The factory-produced controller dismisses itself when the user taps Done or
//  Cancel, then forwards the `onFinish` event to you.
//

import SwiftUI
import UIKit
import PurpleWaveCameraCore

public extension PWCamera {

    /// Builds a full-screen photo capture controller driven by closures.
    static func makePhotoCapture(
        config: PWCameraConfig,
        handlers: PWPhotoHandlers
    ) -> UIViewController {
        let holder = ControllerHolder()

        // Wrap onFinish so the SDK dismisses its own controller before handing
        // control back to the host.
        let wrapped = PWPhotoHandlers(
            onCapture: handlers.onCapture,
            onFinish: { reason in
                holder.controller?.dismiss(animated: true)
                handlers.onFinish(reason)
            },
            onError: handlers.onError
        )

        let controller = UIHostingController(
            rootView: PWCameraScreen(config: config, handlers: wrapped)
        )
        controller.modalPresentationStyle = .fullScreen
        holder.controller = controller
        return controller
    }

    /// Builds a full-screen photo capture controller driven by a delegate.
    /// The delegate is held weakly.
    static func makePhotoCapture(
        config: PWCameraConfig,
        delegate: PWPhotoCaptureDelegate
    ) -> UIViewController {
        let handlers = PWPhotoHandlers(
            onCapture: { [weak delegate] in delegate?.photoCapture(didCapture: $0) },
            onFinish: { [weak delegate] in delegate?.photoCapture(didFinish: $0) },
            onError: { [weak delegate] in delegate?.photoCapture(didFail: $0) }
        )
        return makePhotoCapture(config: config, handlers: handlers)
    }
}
