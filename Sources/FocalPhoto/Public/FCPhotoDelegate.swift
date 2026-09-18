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
public struct FCPhotoHandlers {
    public var onCapture: (FCPhotoResult) -> Void

    /// Called once per library selection with every captured photo it produced.
    ///
    /// Additional to `onCapture`, which still fires per item. Useful when the
    /// host wants to act on the whole set — uploading photos together, say —
    /// rather than one at a time. Defaults to a no-op.
    public var onImport: ([FCPhotoResult]) -> Void
    public var onFinish: (FCFinishReason) -> Void
    public var onError: (FCCameraError) -> Void

    public init(
        onCapture: @escaping (FCPhotoResult) -> Void,
        onImport: @escaping ([FCPhotoResult]) -> Void = { _ in },
        onFinish: @escaping (FCFinishReason) -> Void = { _ in },
        onError: @escaping (FCCameraError) -> Void = { _ in }
    ) {
        self.onCapture = onCapture
        self.onImport = onImport
        self.onFinish = onFinish
        self.onError = onError
    }
}
