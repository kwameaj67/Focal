//
//  MediaPermissions+Microphone.swift
//  PurpleWaveCameraVideo
//
//  Microphone authorization lives in the video target, not in Core, for the
//  same reason microphone *attachment* does: these are the only calls in the
//  SDK that name `AVMediaType.audio`. Keeping them here means a host that links
//  only PurpleWaveCameraPhoto contains no microphone code path, so it needs no
//  `NSMicrophoneUsageDescription` and discloses no microphone access.
//
//  Requesting microphone access without that Info.plist key crashes the app, so
//  this isolation is a correctness property, not just tidiness.
//

import AVFoundation
import PurpleWaveCameraCore

public extension MediaPermissions {

    /// Current microphone authorization without prompting.
    static func microphoneStatus() -> PWPermissionStatus {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    /// Requests microphone access, returning `true` if granted.
    @discardableResult
    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Ensures every permission required by a *video* flow is granted (camera +
    /// microphone, plus library when needed).
    ///
    /// - Returns: `nil` on success, or the first denied permission.
    static func ensureVideoPermissions(
        needsLibrary: Bool
    ) async -> PWPermission? {
        if !(await requestCamera()) { return .camera }
        if !(await requestMicrophone()) { return .microphone }
        if needsLibrary, !(await requestPhotoLibrary()) { return .photoLibrary }
        return nil
    }
}
