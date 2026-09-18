//
//  PreviewSupport.swift
//  FocalCore
//
//  Detects the Xcode preview canvas.
//
//  The capture screens can't do their normal startup in a preview: there is no
//  camera to configure and no host UI to present a permission prompt against,
//  so `requestAccess` never resolves meaningfully and the screen settles on its
//  permission-denied state. That makes the canvas useless for the thing it's
//  good at — iterating on the overlay chrome.
//
//  Screens check this to skip session configuration and permission requests
//  only. Everything else — layout, badges, the settings sheet, the category bar
//  — renders exactly as it does on device, which is the point.
//

import Foundation

extension ProcessInfo {

    /// `true` when running inside the Xcode preview canvas.
    ///
    /// Xcode sets this environment variable for preview processes. It is not
    /// set for the simulator, a device, or unit tests, so this never changes
    /// behaviour in anything a user or CI runs.
    package static var isRunningInXcodePreview: Bool {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
