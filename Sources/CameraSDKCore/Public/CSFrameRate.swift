//
//  CSFrameRate.swift
//  CameraSDKCore
//
//  The capture frame rate offered by both the photo and video screens.
//

import Foundation

/// Supported capture frame rates. 60fps is the default for a smoother preview
/// and smoother recordings; 30fps trades that for smaller files and wider
/// device/format support. When a device or the active format can't reach the
/// requested rate, the SDK falls back to the highest it supports.
public enum CSFrameRate: Int, CaseIterable, Sendable {
    case fps30 = 30
    case fps60 = 60

    /// Short label for the control, e.g. "60 FPS".
    public var title: String { "\(rawValue) FPS" }

    /// The other rate — the two-state toggle used by the on-screen control.
    package var toggled: CSFrameRate { self == .fps60 ? .fps30 : .fps60 }
}
