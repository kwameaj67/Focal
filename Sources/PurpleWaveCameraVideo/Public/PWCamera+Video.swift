//
//  PWCamera+Video.swift
//  PurpleWaveCameraVideo
//
//  UIKit entry point for video recording.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (SwiftUI)
//  ─────────────────────────────────────────────────────────────────────────
//      PWVideoScreen(
//          config: PWVideoConfig(categories: [PWCategory("Walkaround")]),
//          handlers: PWVideoHandlers(onRecord: { result in
//              // persist result.fileURL
//          })
//      )
//
//  ─────────────────────────────────────────────────────────────────────────
//  Quick start (UIKit)
//  ─────────────────────────────────────────────────────────────────────────
//      let vc = PWCamera.makeVideoRecorder(
//          config: PWVideoConfig(categories: [PWCategory("Walkaround")]),
//          handlers: PWVideoHandlers(onRecord: { result in ... })
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

    /// Builds a full-screen video recorder controller driven by closures.
    static func makeVideoRecorder(
        config: PWVideoConfig,
        handlers: PWVideoHandlers
    ) -> UIViewController {
        let holder = ControllerHolder()

        let wrapped = PWVideoHandlers(
            onRecord: handlers.onRecord,
            onFinish: { reason in
                holder.controller?.dismiss(animated: true)
                handlers.onFinish(reason)
            },
            onError: handlers.onError
        )

        let controller = UIHostingController(
            rootView: PWVideoScreen(config: config, handlers: wrapped)
        )
        controller.modalPresentationStyle = .fullScreen
        holder.controller = controller
        return controller
    }

    /// Builds a full-screen video recorder controller driven by a delegate.
    /// The delegate is held weakly.
    static func makeVideoRecorder(
        config: PWVideoConfig,
        delegate: PWVideoRecorderDelegate
    ) -> UIViewController {
        let handlers = PWVideoHandlers(
            onRecord: { [weak delegate] in delegate?.videoRecorder(didRecord: $0) },
            onFinish: { [weak delegate] in delegate?.videoRecorder(didFinish: $0) },
            onError: { [weak delegate] in delegate?.videoRecorder(didFail: $0) }
        )
        return makeVideoRecorder(config: config, handlers: handlers)
    }
}
