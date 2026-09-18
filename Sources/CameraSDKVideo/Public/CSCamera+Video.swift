//
//  CSCamera+Video.swift
//  CameraSDKVideo
//
//  UIKit entry point for video recording.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (SwiftUI)
//  ─────────────────────────────────────────────────────────────────────────
//      CSVideoScreen(
//          config: CSVideoConfig(categories: [CSCategory("Walkaround")]),
//          handlers: CSVideoHandlers(onRecord: { result in
//              // persist result.fileURL
//          })
//      )
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (UIKit)
//  ─────────────────────────────────────────────────────────────────────────
//      let vc = CSCamera.makeVideoRecorder(
//          config: CSVideoConfig(categories: [CSCategory("Walkaround")]),
//          handlers: CSVideoHandlers(onRecord: { result in ... })
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

    /// Builds a full-screen video recorder controller driven by closures.
    static func makeVideoRecorder(
        config: CSVideoConfig,
        handlers: CSVideoHandlers
    ) -> UIViewController {
        let holder = ControllerHolder()

        let wrapped = CSVideoHandlers(
            onRecord: handlers.onRecord,
            onImport: handlers.onImport,
            onFinish: { reason in
                holder.controller?.dismiss(animated: true)
                handlers.onFinish(reason)
            },
            onError: handlers.onError
        )

        let controller = UIHostingController(
            rootView: CSVideoScreen(config: config, handlers: wrapped)
        )
        controller.modalPresentationStyle = .fullScreen
        holder.controller = controller
        return controller
    }

    /// Builds a full-screen video recorder controller driven by a delegate.
    /// The delegate is held weakly.
    static func makeVideoRecorder(
        config: CSVideoConfig,
        delegate: CSVideoRecorderDelegate
    ) -> UIViewController {
        let handlers = CSVideoHandlers(
            onRecord: { [weak delegate] in delegate?.videoRecorder(didRecord: $0) },
            onImport: { [weak delegate] in delegate?.videoRecorder(didImport: $0) },
            onFinish: { [weak delegate] in delegate?.videoRecorder(didFinish: $0) },
            onError: { [weak delegate] in delegate?.videoRecorder(didFail: $0) }
        )
        return makeVideoRecorder(config: config, handlers: handlers)
    }
}
