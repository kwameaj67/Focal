//
//  PWPhotoDelegate.swift
//  PurpleWaveCameraPhoto
//
//  Callback surfaces for photo capture. Two styles are offered — a delegate
//  protocol for UIKit-style consumers, and a closure "handlers" bundle for
//  SwiftUI-style consumers. Both deliver the same events.
//

import Foundation
import PurpleWaveCameraCore

/// Receives events from a photo capture screen. All methods are optional via
/// the default implementations below.
public protocol PWPhotoCaptureDelegate: AnyObject {
    /// Called once per captured (or imported) photo. May fire multiple times
    /// because the capture screen stays open for multi-shot workflows.
    func photoCapture(didCapture result: PWPhotoResult)

    /// Called when the user leaves the screen (Done or Cancel).
    func photoCapture(didFinish reason: PWFinishReason)

    /// Called when a recoverable error occurs (e.g. a single failed capture).
    func photoCapture(didFail error: PWCameraError)
}

public extension PWPhotoCaptureDelegate {
    func photoCapture(didFinish reason: PWFinishReason) {}
    func photoCapture(didFail error: PWCameraError) {}
}

/// Closure-based equivalent of `PWPhotoCaptureDelegate`, convenient for SwiftUI
/// and one-off presentations.
public struct PWPhotoHandlers {
    public var onCapture: (PWPhotoResult) -> Void
    public var onFinish: (PWFinishReason) -> Void
    public var onError: (PWCameraError) -> Void

    public init(
        onCapture: @escaping (PWPhotoResult) -> Void,
        onFinish: @escaping (PWFinishReason) -> Void = { _ in },
        onError: @escaping (PWCameraError) -> Void = { _ in }
    ) {
        self.onCapture = onCapture
        self.onFinish = onFinish
        self.onError = onError
    }
}
