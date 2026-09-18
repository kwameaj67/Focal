//
//  MediaPermissions+Microphone.swift
//  FocalVideo
//
//  Microphone authorization lives in the video target, not in Core, for the
//  same reason microphone *attachment* does: these are the only calls in the
//  SDK that name `AVMediaType.audio`. Keeping them here means a host that links
//  only FocalPhoto contains no microphone code path, so it needs no
//  `NSMicrophoneUsageDescription` and discloses no microphone access.
//
//  Requesting microphone access without that Info.plist key crashes the app, so
//  this isolation is a correctness property, not just tidiness.
//

import AVFoundation
import FocalCore

public extension MediaPermissions {

    /// Current microphone authorization without prompting.
    static func microphoneStatus() -> FCPermissionStatus {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    /// Requests microphone access, returning `true` if granted.
    @discardableResult
    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Ensures every permission required to *start recording* is granted:
    /// camera and microphone.
    ///
    /// Library access is deliberately not included — it is requested when the
    /// user opens the gallery, and add-only when a recording is saved.
    ///
    /// - Returns: `nil` on success, or the first denied permission.
    static func ensureVideoPermissions() async -> FCPermission? {
        if !(await requestCamera()) { return .camera }
        if !(await requestMicrophone()) { return .microphone }
        return nil
    }
}
