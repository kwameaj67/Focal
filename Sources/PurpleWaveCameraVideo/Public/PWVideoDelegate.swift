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
}

public extension PWVideoRecorderDelegate {
    func videoRecorder(didFinish reason: PWFinishReason) {}
    func videoRecorder(didFail error: PWCameraError) {}
}

/// Closure-based equivalent of `PWVideoRecorderDelegate`.
public struct PWVideoHandlers {
    public var onRecord: (PWVideoResult) -> Void
    public var onFinish: (PWFinishReason) -> Void
    public var onError: (PWCameraError) -> Void

    public init(
        onRecord: @escaping (PWVideoResult) -> Void,
        onFinish: @escaping (PWFinishReason) -> Void = { _ in },
        onError: @escaping (PWCameraError) -> Void = { _ in }
    ) {
        self.onRecord = onRecord
        self.onFinish = onFinish
        self.onError = onError
    }
}
