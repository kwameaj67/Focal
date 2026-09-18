//
//  CSCameraConfig.swift
//  CameraSDKPhoto
//
//  Configuration for the photo capture screen.
//

import UIKit
import AVFoundation
import CameraSDKCore

/// Flash behaviour for photo capture. Mirrors `AVCaptureDevice.FlashMode`
/// without leaking AVFoundation into the public API.
public enum CSFlashMode: Sendable {
    case auto
    case on
    case off

    /// Bridges to the AVFoundation type used by the capture engine.
    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on:   return .on
        case .off:  return .off
        }
    }
}

/// Everything the host can tune about the photo capture screen.
///
/// All fields have sensible defaults, so `CSCameraConfig()` gives you a working
/// camera with no categories, auto flash, gallery + ultra-wide enabled, and
/// output written to a temporary directory.
public struct CSCameraConfig {

    /// Categories rendered in the horizontal scroll selector. Pass an empty
    /// array to hide the selector entirely.
    public var categories: [CSCategory]

    /// The category selected when the screen first appears. If `nil` (or not
    /// found) the first category is used.
    public var startingCategoryID: String?

    /// Flash mode applied on launch.
    public var defaultFlashMode: CSFlashMode

    /// Frame rate the camera preview starts at. Default `.fps60`; the user can
    /// switch to 30fps from the on-screen control. Falls back to the highest the
    /// device and active format support.
    public var defaultFrameRate: CSFrameRate

    /// Shows the "select from library" button and enables the built-in gallery.
    public var allowsGallery: Bool

    /// Shows the ultra-wide toggle (only effective on devices with an
    /// ultra-wide camera).
    public var allowsUltraWide: Bool

    /// When `true`, captured photos are also saved to the system photo library
    /// (requires `NSPhotoLibraryAddUsageDescription`). Default `false` — the
    /// host usually persists media itself via the capture callback.
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

    /// Optional label rendered as a badge in the top-right corner (e.g. to
    /// show an item or sticker ID). `nil` hides the badge.
    public var overlayLabel: String?

    /// Directory where encoded image files may be written if the host uses the
    /// file-based helpers. `nil` uses `FileManager`'s temporary directory.
    public var outputDirectory: URL?

    public init(
        categories: [CSCategory] = [],
        startingCategoryID: String? = nil,
        defaultFlashMode: CSFlashMode = .auto,
        defaultFrameRate: CSFrameRate = .fps60,
        allowsGallery: Bool = true,
        allowsUltraWide: Bool = true,
        savesToPhotoLibrary: Bool = false,
        capturesLocation: Bool = false,
        overlayLabel: String? = nil,
        outputDirectory: URL? = nil
    ) {
        self.categories = categories
        self.startingCategoryID = startingCategoryID
        self.defaultFlashMode = defaultFlashMode
        self.defaultFrameRate = defaultFrameRate
        self.allowsGallery = allowsGallery
        self.allowsUltraWide = allowsUltraWide
        self.savesToPhotoLibrary = savesToPhotoLibrary
        self.capturesLocation = capturesLocation
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
}
