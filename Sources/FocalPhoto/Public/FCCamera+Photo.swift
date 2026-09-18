//
//  FCCamera+Photo.swift
//  FocalPhoto
//
//  UIKit entry point for photo capture.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (SwiftUI)
//  ─────────────────────────────────────────────────────────────────────────
//      FCCameraScreen(
//          config: FCCameraConfig(categories: [FCCategory("Profile")]),
//          handlers: FCPhotoHandlers(onCapture: { result in
//              // persist result.imageData / result.image
//          })
//      )
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (UIKit)
//  ─────────────────────────────────────────────────────────────────────────
//      let vc = FCCamera.makePhotoCapture(
//          config: FCCameraConfig(categories: [FCCategory("Profile")]),
//          handlers: FCPhotoHandlers(onCapture: { result in ... })
//      )
//      present(vc, animated: true)
//
//  The factory-produced controller dismisses itself when the user taps Done or
//  Cancel, then forwards the `onFinish` event to you.
//

import SwiftUI
import UIKit
import FocalCore

public extension FCCamera {

    /// Builds a full-screen photo capture controller driven by closures.
    static func makePhotoCapture(
        config: FCCameraConfig,
        handlers: FCPhotoHandlers
    ) -> UIViewController {
        let holder = ControllerHolder()

        // Wrap onFinish so the SDK dismisses its own controller before handing
        // control back to the host.
        let wrapped = FCPhotoHandlers(
            onCapture: handlers.onCapture,
            onImport: handlers.onImport,
            onFinish: { reason in
                holder.controller?.dismiss(animated: true)
                handlers.onFinish(reason)
            },
            onError: handlers.onError
        )

        let controller = UIHostingController(
            rootView: FCCameraScreen(config: config, handlers: wrapped)
        )
        controller.modalPresentationStyle = .fullScreen
        holder.controller = controller
        return controller
    }

    /// Builds a full-screen photo capture controller driven by a delegate.
    /// The delegate is held weakly.
    static func makePhotoCapture(
        config: FCCameraConfig,
        delegate: FCPhotoCaptureDelegate
    ) -> UIViewController {
        let handlers = FCPhotoHandlers(
            onCapture: { [weak delegate] in delegate?.photoCapture(didCapture: $0) },
            onImport: { [weak delegate] in delegate?.photoCapture(didImport: $0) },
            onFinish: { [weak delegate] in delegate?.photoCapture(didFinish: $0) },
            onError: { [weak delegate] in delegate?.photoCapture(didFail: $0) }
        )
        return makePhotoCapture(config: config, handlers: handlers)
    }
}
