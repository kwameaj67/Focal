//
//  FCPhotoDelegate.swift
//  FocalPhoto
//
//  Callback surfaces for photo capture. Two styles are offered — a delegate
//  protocol for UIKit-style consumers, and a closure "handlers" bundle for
//  SwiftUI-style consumers. Both deliver the same events.
//

import Foundation
import FocalCore

/// Receives events from a photo capture screen. All methods are optional via
/// the default implementations below.
///
/// **Threading:** every method is called on the **main thread**, so it is safe
/// to update UIKit / SwiftUI state directly from them without hopping queues.
public protocol FCPhotoCaptureDelegate: AnyObject {
    /// Called once per captured (or imported) photo. May fire multiple times
    /// because the capture screen stays open for multi-shot workflows.
    func photoCapture(didCapture result: FCPhotoResult)

    /// Called when the user leaves the screen (Done or Cancel).
    func photoCapture(didFinish reason: FCFinishReason)

    /// Called when a recoverable error occurs (e.g. a single failed capture).
    func photoCapture(didFail error: FCCameraError)

    /// Called once when a library selection finishes importing, with every
    /// result from that selection.
    ///
    /// The per-item callback still fires for each one; this is in addition, for
    /// hosts that want the set rather than a stream. Only successful imports
    /// appear, so the count can be smaller than the number of assets picked.
    func photoCapture(didImport results: [FCPhotoResult])
}

public extension FCPhotoCaptureDelegate {
    func photoCapture(didFinish reason: FCFinishReason) {}
    func photoCapture(didFail error: FCCameraError) {}
    func photoCapture(didImport results: [FCPhotoResult]) {}
}

/// Closure-based equivalent of `FCPhotoCaptureDelegate`, convenient for SwiftUI
/// and one-off presentations.
///
/// **Threading:** every closure is called on the **main thread**. The init
/// wraps each one in a main-thread hop, so the guarantee holds no matter which
/// internal queue produced the event — you can update UI state directly inside
/// them. The properties are read-only from outside for the same reason: the
/// guarantee is established at construction.
public struct FCPhotoHandlers {
    public private(set) var onCapture: (FCPhotoResult) -> Void

    /// Called once per library selection with every captured photo it produced.
    ///
    /// Additional to `onCapture`, which still fires per item. Useful when the
    /// host wants to act on the whole set — uploading photos together, say —
    /// rather than one at a time. Defaults to a no-op.
    public private(set) var onImport: ([FCPhotoResult]) -> Void
    public private(set) var onFinish: (FCFinishReason) -> Void
    public private(set) var onError: (FCCameraError) -> Void

    public init(
        onCapture: @escaping (FCPhotoResult) -> Void,
        onImport: @escaping ([FCPhotoResult]) -> Void = { _ in },
        onFinish: @escaping (FCFinishReason) -> Void = { _ in },
        onError: @escaping (FCCameraError) -> Void = { _ in }
    ) {
        // Deliver every event on the main thread so hosts can drive UI directly.
        self.onCapture = { result in onMainThread { onCapture(result) } }
        self.onImport = { results in onMainThread { onImport(results) } }
        self.onFinish = { reason in onMainThread { onFinish(reason) } }
        self.onError = { error in onMainThread { onError(error) } }
    }
}
