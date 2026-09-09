//
//  PWPhotoResult.swift
//  PurpleWaveCameraPhoto
//
//  What the host receives for a single captured or imported photo.
//

import UIKit
import CoreLocation
import PurpleWaveCameraCore

/// The result of a single photo capture (or a single gallery import).
public struct PWPhotoResult {

    /// Encoded image data (HEVC/JPEG depending on device support), suitable for
    /// writing to disk or uploading.
    public let imageData: Data

    /// A ready-to-display `UIImage` decoded from `imageData`.
    public let image: UIImage

    /// The category selected in the scroll bar when this photo was taken.
    /// `nil` if the host configured no categories.
    public let category: PWCategory?

    /// Whether the photo was captured live or imported from the library.
    public let source: PWCaptureSource

    /// The device orientation at capture time — useful for downstream display
    /// or re-orientation decisions.
    public let orientation: UIDeviceOrientation

    /// Optional capture metadata (EXIF etc.), when available.
    public let metadata: [String: Any]?

    /// Where the device was when this was captured, when the host opted into
    /// location via `capturesLocation` and a fix was available. `nil` when
    /// location is off, denied, or the fix failed — a missing fix never blocks
    /// a capture.
    public let location: CLLocation?

    /// When this was captured. For a gallery import this is the time of the
    /// import, not the asset's original creation date.
    public let capturedAt: Date

    public init(
        imageData: Data,
        image: UIImage,
        category: PWCategory?,
        source: PWCaptureSource,
        orientation: UIDeviceOrientation,
        metadata: [String: Any]? = nil,
        location: CLLocation? = nil,
        capturedAt: Date = Date()
    ) {
        self.imageData = imageData
        self.image = image
        self.category = category
        self.source = source
        self.orientation = orientation
        self.metadata = metadata
        self.location = location
        self.capturedAt = capturedAt
    }
}
