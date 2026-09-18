//
//  CSVideoDelegate.swift
//  CameraSDKVideo
//
//  Callback surfaces for video recording. Two styles are offered — a delegate
//  protocol for UIKit-style consumers, and a closure "handlers" bundle for
//  SwiftUI-style consumers. Both deliver the same events.
//

import Foundation
import CameraSDKCore

/// Receives events from a video recorder screen.
public protocol CSVideoRecorderDelegate: AnyObject {
    /// Called once per recorded (or imported) video.
    func videoRecorder(didRecord result: CSVideoResult)

    /// Called when the user leaves the screen (Done or Cancel).
    func videoRecorder(didFinish reason: CSFinishReason)

    /// Called when a recoverable error occurs.
    func videoRecorder(didFail error: CSCameraError)

    /// Called once when a library selection finishes importing, with every
    /// result from that selection.
    ///
    /// The per-item callback still fires for each one; this is in addition, for
    /// hosts that want the set rather than a stream. Only successful imports
    /// appear, so the count can be smaller than the number of assets picked.
    func videoRecorder(didImport results: [CSVideoResult])
}

public extension CSVideoRecorderDelegate {
    func videoRecorder(didFinish reason: CSFinishReason) {}
    func videoRecorder(didFail error: CSCameraError) {}
    func videoRecorder(didImport results: [CSVideoResult]) {}
}

/// Closure-based equivalent of `CSVideoRecorderDelegate`.
public struct CSVideoHandlers {
    public var onRecord: (CSVideoResult) -> Void

    /// Called once per library selection with every recorded video it produced.
    ///
    /// Additional to `onRecord`, which still fires per item. Useful when the
    /// host wants to act on the whole set — uploading videos together, say —
    /// rather than one at a time. Defaults to a no-op.
    public var onImport: ([CSVideoResult]) -> Void
    public var onFinish: (CSFinishReason) -> Void
    public var onError: (CSCameraError) -> Void

    public init(
        onRecord: @escaping (CSVideoResult) -> Void,
        onImport: @escaping ([CSVideoResult]) -> Void = { _ in },
        onFinish: @escaping (CSFinishReason) -> Void = { _ in },
        onError: @escaping (CSCameraError) -> Void = { _ in }
    ) {
        self.onRecord = onRecord
        self.onImport = onImport
        self.onFinish = onFinish
        self.onError = onError
    }
}
