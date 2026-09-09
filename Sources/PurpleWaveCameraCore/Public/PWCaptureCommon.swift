//
//  PWCaptureCommon.swift
//  PurpleWaveCameraCore
//
//  The result-adjacent values both capture modes share: where media came from,
//  why a screen finished, and the error type. The per-mode result structs live
//  with their own targets, in PWPhotoResult / PWVideoResult.
//

import Foundation

/// Where a piece of media came from.
public enum PWCaptureSource: Sendable {
    /// Captured live with the device camera.
    case camera
    /// Imported from the photo library via the built-in gallery picker.
    case gallery
}

/// Why a capture screen finished / was dismissed.
public enum PWFinishReason: Sendable {
    /// The user tapped "Done" (they captured at least one item, or chose to
    /// finish). The host typically dismisses the screen here.
    case done
    /// The user tapped "Cancel" without an explicit completion.
    case cancelled
}

/// Errors surfaced by the SDK to the host.
///
/// Both capture modes throw from this one type, so a host can handle SDK errors
/// in a single place regardless of which screen produced them.
public enum PWCameraError: Error {
    /// A required permission (camera, microphone, or photo library) was denied.
    case permissionDenied(PWPermission)
    /// The capture session could not be configured (no camera, input failure…).
    case sessionConfigurationFailed(String)
    /// A photo capture failed to produce image data.
    case photoCaptureFailed(String)
    /// A video recording failed.
    case videoRecordingFailed(String)
}
