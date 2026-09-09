//
//  PWCameraConfig.swift
//  PurpleWaveCameraPhoto
//
//  Configuration for the photo capture screen.
//

import UIKit
import AVFoundation
import PurpleWaveCameraCore

/// Flash behaviour for photo capture. Mirrors `AVCaptureDevice.FlashMode`
/// without leaking AVFoundation into the public API.
public enum PWFlashMode: Sendable {
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
/// All fields have sensible defaults, so `PWCameraConfig()` gives you a working
/// camera with no categories, auto flash, gallery + ultra-wide enabled, and
/// output written to a temporary directory.
public struct PWCameraConfig {

    /// Categories rendered in the horizontal scroll selector. Pass an empty
    /// array to hide the selector entirely.
    public var categories: [PWCategory]

    /// The category selected when the screen first appears. If `nil` (or not
    /// found) the first category is used.
    public var startingCategoryID: String?

    /// Flash mode applied on launch.
    public var defaultFlashMode: PWFlashMode

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

    /// Optional label rendered as a badge in the top-right corner (used by
    /// FieldTool to show the sticker ID). `nil` hides the badge.
    public var overlayLabel: String?

    /// Directory where encoded image files may be written if the host uses the
    /// file-based helpers. `nil` uses `FileManager`'s temporary directory.
    public var outputDirectory: URL?

    public init(
        categories: [PWCategory] = [],
        startingCategoryID: String? = nil,
        defaultFlashMode: PWFlashMode = .auto,
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
        self.allowsGallery = allowsGallery
        self.allowsUltraWide = allowsUltraWide
        self.savesToPhotoLibrary = savesToPhotoLibrary
        self.capturesLocation = capturesLocation
        self.overlayLabel = overlayLabel
        self.outputDirectory = outputDirectory
    }

    /// The category to select at launch, resolving `startingCategoryID`.
    var initialCategory: PWCategory? {
        if let id = startingCategoryID,
           let match = categories.first(where: { $0.id == id }) {
            return match
        }
        return categories.first
    }
}
