//
//  CSCamera+Photo.swift
//  CameraSDKPhoto
//
//  UIKit entry point for photo capture.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (SwiftUI)
//  ─────────────────────────────────────────────────────────────────────────
//      CSCameraScreen(
//          config: CSCameraConfig(categories: [CSCategory("Profile")]),
//          handlers: CSPhotoHandlers(onCapture: { result in
//              // persist result.imageData / result.image
//          })
//      )
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (UIKit)
//  ─────────────────────────────────────────────────────────────────────────
//      let vc = CSCamera.makePhotoCapture(
//          config: CSCameraConfig(categories: [CSCategory("Profile")]),
//          handlers: CSPhotoHandlers(onCapture: { result in ... })
//      )
//      present(vc, animated: true)
//
//  The factory-produced controller dismisses itself when the user taps Done or
//  Cancel, then forwards the `onFinish` event to you.
//

import SwiftUI
import UIKit
import CameraSDKCore

public extension CSCamera {

    /// Builds a full-screen photo capture controller driven by closures.
    static func makePhotoCapture(
        config: CSCameraConfig,
        handlers: CSPhotoHandlers
    ) -> UIViewController {
        let holder = ControllerHolder()

        // Wrap onFinish so the SDK dismisses its own controller before handing
        // control back to the host.
        let wrapped = CSPhotoHandlers(
            onCapture: handlers.onCapture,
            onImport: handlers.onImport,
            onFinish: { reason in
                holder.controller?.dismiss(animated: true)
                handlers.onFinish(reason)
            },
            onError: handlers.onError
        )

        let controller = UIHostingController(
            rootView: CSCameraScreen(config: config, handlers: wrapped)
        )
        controller.modalPresentationStyle = .fullScreen
        holder.controller = controller
        return controller
    }

    /// Builds a full-screen photo capture controller driven by a delegate.
    /// The delegate is held weakly.
    static func makePhotoCapture(
        config: CSCameraConfig,
        delegate: CSPhotoCaptureDelegate
    ) -> UIViewController {
        let handlers = CSPhotoHandlers(
            onCapture: { [weak delegate] in delegate?.photoCapture(didCapture: $0) },
            onImport: { [weak delegate] in delegate?.photoCapture(didImport: $0) },
            onFinish: { [weak delegate] in delegate?.photoCapture(didFinish: $0) },
            onError: { [weak delegate] in delegate?.photoCapture(didFail: $0) }
        )
        return makePhotoCapture(config: config, handlers: handlers)
    }
}
