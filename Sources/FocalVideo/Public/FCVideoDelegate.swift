//
//  FCVideoDelegate.swift
//  FocalVideo
//
//  Callback surfaces for video recording. Two styles are offered — a delegate
//  protocol for UIKit-style consumers, and a closure "handlers" bundle for
//  SwiftUI-style consumers. Both deliver the same events.
//

import Foundation
import FocalCore

/// Receives events from a video recorder screen.
///
/// **Threading:** every method is called on the **main thread**, so it is safe
/// to update UIKit / SwiftUI state directly from them without hopping queues.
public protocol FCVideoRecorderDelegate: AnyObject {
    /// Called once per recorded (or imported) video.
    func videoRecorder(didRecord result: FCVideoResult)

    /// Called when the user leaves the screen (Done or Cancel).
    func videoRecorder(didFinish reason: FCFinishReason)

    /// Called when a recoverable error occurs.
    func videoRecorder(didFail error: FCCameraError)

    /// Called once when a library selection finishes importing, with every
    /// result from that selection.
    ///
    /// The per-item callback still fires for each one; this is in addition, for
    /// hosts that want the set rather than a stream. Only successful imports
    /// appear, so the count can be smaller than the number of assets picked.
    func videoRecorder(didImport results: [FCVideoResult])
}

public extension FCVideoRecorderDelegate {
    func videoRecorder(didFinish reason: FCFinishReason) {}
    func videoRecorder(didFail error: FCCameraError) {}
    func videoRecorder(didImport results: [FCVideoResult]) {}
}

/// Closure-based equivalent of `FCVideoRecorderDelegate`.
///
/// **Threading:** every closure is called on the **main thread**. The init
/// wraps each one in a main-thread hop, so the guarantee holds no matter which
/// internal queue produced the event — you can update UI state directly inside
/// them. The properties are read-only from outside for the same reason: the
/// guarantee is established at construction.
public struct FCVideoHandlers {
    public private(set) var onRecord: (FCVideoResult) -> Void

    /// Called once per library selection with every recorded video it produced.
    ///
    /// Additional to `onRecord`, which still fires per item. Useful when the
    /// host wants to act on the whole set — uploading videos together, say —
    /// rather than one at a time. Defaults to a no-op.
    public private(set) var onImport: ([FCVideoResult]) -> Void
    public private(set) var onFinish: (FCFinishReason) -> Void
    public private(set) var onError: (FCCameraError) -> Void

    public init(
        onRecord: @escaping (FCVideoResult) -> Void,
        onImport: @escaping ([FCVideoResult]) -> Void = { _ in },
        onFinish: @escaping (FCFinishReason) -> Void = { _ in },
        onError: @escaping (FCCameraError) -> Void = { _ in }
    ) {
        // Deliver every event on the main thread so hosts can drive UI directly.
        self.onRecord = { result in onMainThread { onRecord(result) } }
        self.onImport = { results in onMainThread { onImport(results) } }
        self.onFinish = { reason in onMainThread { onFinish(reason) } }
        self.onError = { error in onMainThread { onError(error) } }
    }
}
