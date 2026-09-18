//
//  FCCamera+Video.swift
//  FocalVideo
//
//  UIKit entry point for video recording.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (SwiftUI)
//  ─────────────────────────────────────────────────────────────────────────
//      FCVideoScreen(
//          config: FCVideoConfig(categories: [FCCategory("Walkaround")]),
//          handlers: FCVideoHandlers(onRecord: { result in
//              // persist result.fileURL
//          })
//      )
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (UIKit)
//  ─────────────────────────────────────────────────────────────────────────
//      let vc = FCCamera.makeVideoRecorder(
//          config: FCVideoConfig(categories: [FCCategory("Walkaround")]),
//          handlers: FCVideoHandlers(onRecord: { result in ... })
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

    /// Builds a full-screen video recorder controller driven by closures.
    static func makeVideoRecorder(
        config: FCVideoConfig,
        handlers: FCVideoHandlers
    ) -> UIViewController {
        let holder = ControllerHolder()

        let wrapped = FCVideoHandlers(
            onRecord: handlers.onRecord,
            onImport: handlers.onImport,
            onFinish: { reason in
                holder.controller?.dismiss(animated: true)
                handlers.onFinish(reason)
            },
            onError: handlers.onError
        )

        let controller = UIHostingController(
            rootView: FCVideoScreen(config: config, handlers: wrapped)
        )
        controller.modalPresentationStyle = .fullScreen
        holder.controller = controller
        return controller
    }

    /// Builds a full-screen video recorder controller driven by a delegate.
    /// The delegate is held weakly.
    static func makeVideoRecorder(
        config: FCVideoConfig,
        delegate: FCVideoRecorderDelegate
    ) -> UIViewController {
        let handlers = FCVideoHandlers(
            onRecord: { [weak delegate] in delegate?.videoRecorder(didRecord: $0) },
            onImport: { [weak delegate] in delegate?.videoRecorder(didImport: $0) },
            onFinish: { [weak delegate] in delegate?.videoRecorder(didFinish: $0) },
            onError: { [weak delegate] in delegate?.videoRecorder(didFail: $0) }
        )
        return makeVideoRecorder(config: config, handlers: handlers)
    }
}
