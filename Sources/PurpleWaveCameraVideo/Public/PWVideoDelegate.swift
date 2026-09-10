//
//  PWVideoDelegate.swift
//  PurpleWaveCameraVideo
//
//  Callback surfaces for video recording. Two styles are offered — a delegate
//  protocol for UIKit-style consumers, and a closure "handlers" bundle for
//  SwiftUI-style consumers. Both deliver the same events.
//

import Foundation
import PurpleWaveCameraCore

/// Receives events from a video recorder screen.
public protocol PWVideoRecorderDelegate: AnyObject {
    /// Called once per recorded (or imported) video.
    func videoRecorder(didRecord result: PWVideoResult)

    /// Called when the user leaves the screen (Done or Cancel).
    func videoRecorder(didFinish reason: PWFinishReason)

    /// Called when a recoverable error occurs.
    func videoRecorder(didFail error: PWCameraError)

    /// Called once when a library selection finishes importing, with every
    /// result from that selection.
    ///
    /// The per-item callback still fires for each one; this is in addition, for
    /// hosts that want the set rather than a stream. Only successful imports
    /// appear, so the count can be smaller than the number of assets picked.
    func videoRecorder(didImport results: [PWVideoResult])
}

public extension PWVideoRecorderDelegate {
    func videoRecorder(didFinish reason: PWFinishReason) {}
    func videoRecorder(didFail error: PWCameraError) {}
    func videoRecorder(didImport results: [PWVideoResult]) {}
}

/// Closure-based equivalent of `PWVideoRecorderDelegate`.
public struct PWVideoHandlers {
    public var onRecord: (PWVideoResult) -> Void

    /// Called once per library selection with every recorded video it produced.
    ///
    /// Additional to `onRecord`, which still fires per item. Useful when the
    /// host wants to act on the whole set — uploading videos together, say —
    /// rather than one at a time. Defaults to a no-op.
    public var onImport: ([PWVideoResult]) -> Void
    public var onFinish: (PWFinishReason) -> Void
    public var onError: (PWCameraError) -> Void

    public init(
        onRecord: @escaping (PWVideoResult) -> Void,
        onImport: @escaping ([PWVideoResult]) -> Void = { _ in },
        onFinish: @escaping (PWFinishReason) -> Void = { _ in },
        onError: @escaping (PWCameraError) -> Void = { _ in }
    ) {
        self.onRecord = onRecord
        self.onImport = onImport
        self.onFinish = onFinish
        self.onError = onError
    }
}
