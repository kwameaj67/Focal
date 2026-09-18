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
public struct FCVideoHandlers {
    public var onRecord: (FCVideoResult) -> Void

    /// Called once per library selection with every recorded video it produced.
    ///
    /// Additional to `onRecord`, which still fires per item. Useful when the
    /// host wants to act on the whole set — uploading videos together, say —
    /// rather than one at a time. Defaults to a no-op.
    public var onImport: ([FCVideoResult]) -> Void
    public var onFinish: (FCFinishReason) -> Void
    public var onError: (FCCameraError) -> Void

    public init(
        onRecord: @escaping (FCVideoResult) -> Void,
        onImport: @escaping ([FCVideoResult]) -> Void = { _ in },
        onFinish: @escaping (FCFinishReason) -> Void = { _ in },
        onError: @escaping (FCCameraError) -> Void = { _ in }
    ) {
        self.onRecord = onRecord
        self.onImport = onImport
        self.onFinish = onFinish
        self.onError = onError
    }
}
