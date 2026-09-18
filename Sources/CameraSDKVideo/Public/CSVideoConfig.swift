//
//  CSVideoConfig.swift
//  CameraSDKVideo
//
//  Configuration for the landscape video recorder screen.
//

import UIKit
import AVFoundation
import CameraSDKCore

/// Everything the host can tune about the video recorder screen.
public struct CSVideoConfig {

    /// Categories rendered in the segmented control (e.g. Driving / Functional
    /// / Engine). Pass an empty array to hide it.
    public var categories: [CSCategory]

    /// When `true`, recording is restricted to landscape: in portrait the screen
    /// shows a "rotate to landscape" overlay and disables the record button.
    /// Default `false` — the recorder captures in whatever orientation the
    /// device is held.
    public var landscapeOnly: Bool

    /// The category selected when the screen first appears.
    public var startingCategoryID: String?

    /// Optional hard cap on a single recording's length, in seconds. When set,
    /// recording auto-stops at the limit. `nil` means no limit.
    public var maxDuration: TimeInterval?

    /// Optional per-category capture-quality preset. If a category is missing
    /// here, `defaultPreset` is used.
    public var presetByCategoryID: [String: CSVideoQuality]

    /// Quality preset used for categories not listed in `presetByCategoryID`.
    public var defaultPreset: CSVideoQuality

    /// Frame rate the recorder starts at. Default `.fps60`; the user can switch
    /// to 30fps from the on-screen control. Falls back to the highest the device
    /// and active format support.
    public var defaultFrameRate: CSFrameRate

    /// Shows the torch (flashlight) button.
    public var allowsTorch: Bool

    /// Shows the ultra-wide toggle.
    public var allowsUltraWide: Bool

    /// Shows the "select from library" button and enables the video gallery.
    public var allowsGallery: Bool

    /// When `true`, recorded videos are also saved to the system photo library
    /// (requires `NSPhotoLibraryAddUsageDescription`).
    public var savesToPhotoLibrary: Bool

    /// When `true`, captures are tagged with the device's location and the
    /// screen requests when-in-use authorization on appear.
    ///
    /// Default `false`. Location is opt-in because turning it on adds a
    /// permission prompt, an App Store privacy disclosure, and a requirement
    /// for `NSLocationWhenInUseUsageDescription` in the host's Info.plist —
    /// requesting without that key crashes the app. A failed or denied fix
    /// never blocks a capture; the result just carries no location.
    public var capturesLocation: Bool

    /// Reject imported/recorded videos larger than this many megabytes. The
    /// default is 400 MB.
    public var maxFileSizeMB: Double

    /// Optional top-right badge label (e.g. an item / sticker ID).
    public var overlayLabel: String?

    /// Directory where recorded movies are written. `nil` uses a temporary
    /// directory managed by the SDK.
    public var outputDirectory: URL?

    public init(
        categories: [CSCategory] = [],
        landscapeOnly: Bool = false,
        startingCategoryID: String? = nil,
        maxDuration: TimeInterval? = nil,
        presetByCategoryID: [String: CSVideoQuality] = [:],
        defaultPreset: CSVideoQuality = .hd1080,
        defaultFrameRate: CSFrameRate = .fps60,
        allowsTorch: Bool = true,
        allowsUltraWide: Bool = true,
        allowsGallery: Bool = true,
        savesToPhotoLibrary: Bool = false,
        capturesLocation: Bool = false,
        maxFileSizeMB: Double = 400,
        overlayLabel: String? = nil,
        outputDirectory: URL? = nil
    ) {
        self.categories = categories
        self.landscapeOnly = landscapeOnly
        self.startingCategoryID = startingCategoryID
        self.maxDuration = maxDuration
        self.presetByCategoryID = presetByCategoryID
        self.defaultPreset = defaultPreset
        self.defaultFrameRate = defaultFrameRate
        self.allowsTorch = allowsTorch
        self.allowsUltraWide = allowsUltraWide
        self.allowsGallery = allowsGallery
        self.savesToPhotoLibrary = savesToPhotoLibrary
        self.capturesLocation = capturesLocation
        self.maxFileSizeMB = maxFileSizeMB
        self.overlayLabel = overlayLabel
        self.outputDirectory = outputDirectory
    }

    /// The category to select at launch, resolving `startingCategoryID`.
    var initialCategory: CSCategory? {
        if let id = startingCategoryID,
           let match = categories.first(where: { $0.id == id }) {
            return match
        }
        return categories.first
    }

    /// Resolves the capture preset for a given category.
    func preset(for category: CSCategory?) -> CSVideoQuality {
        guard let id = category?.id else { return defaultPreset }
        return presetByCategoryID[id] ?? defaultPreset
    }
}

/// Capture-quality presets, bridged to `AVCaptureSession.Preset`.
public enum CSVideoQuality: Sendable {
    /// 1920×1080.
    case hd1080
    /// 1280×720.
    case hd720

    var avPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080: return .hd1920x1080
        case .hd720:  return .hd1280x720
        }
    }
}
