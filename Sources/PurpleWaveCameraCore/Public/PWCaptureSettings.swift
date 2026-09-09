//
//  PWCaptureSettings.swift
//  PurpleWaveCameraCore
//
//  The user-adjustable capture settings surfaced in the settings sheet:
//  aspect ratio and the self-timer. Flash lives on the photo config and
//  exposure is a continuous device value, so neither needs an enum here.
//

import CoreGraphics
import Foundation

/// Framing ratio for capture.
///
/// Expressed width-over-height in landscape terms; the screens flip it for
/// portrait. `.fourThree` matches the sensor's native photo output, so it is
/// the only option that never discards pixels.
public enum PWAspectRatio: String, CaseIterable, Sendable {
    case fourThree
    case sixteenNine
    case oneOne

    /// Label shown in the selector.
    public var title: String {
        switch self {
        case .fourThree:   return "4:3"
        case .sixteenNine: return "16:9"
        case .oneOne:      return "1:1"
        }
    }

    /// Long edge ÷ short edge. `1` for square.
    public var ratio: CGFloat {
        switch self {
        case .fourThree:   return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .oneOne:      return 1.0
        }
    }

    /// The ratio as width ÷ height for the given orientation, so the preview
    /// frame and the capture crop agree on which way round it goes.
    public func ratio(isLandscape: Bool) -> CGFloat {
        self == .oneOne ? 1 : (isLandscape ? ratio : 1 / ratio)
    }

    /// Whether selecting this discards sensor data on capture. Only `.fourThree`
    /// is native; the others are cropped from it.
    public var croppedFromSensor: Bool { self != .fourThree }
}

/// Self-timer delay applied before a capture starts.
public enum PWCaptureTimer: Int, CaseIterable, Sendable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    /// Label shown in the wheel.
    public var title: String {
        self == .off ? "Off" : "\(rawValue)s"
    }

    public var isOn: Bool { self != .off }
}
