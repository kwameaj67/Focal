//
//  FCVideoResult.swift
//  FocalVideo
//
//  What the host receives for a single recorded or imported movie.
//

import UIKit
import CoreLocation
import FocalCore

/// The result of a single video recording (or a single gallery import).
public struct FCVideoResult {

    /// Local file URL of the recorded / imported movie. The file lives in the
    /// output directory supplied in `FCVideoConfig` (or a temp directory).
    /// Ownership transfers to the host — move or delete it as needed.
    public let fileURL: URL

    /// The category selected in the segment control when recording started.
    public let category: FCCategory?

    /// Duration of the movie in seconds.
    public let duration: TimeInterval

    /// A first-frame thumbnail, when one could be generated.
    public let thumbnail: UIImage?

    /// Whether the video was recorded live or imported from the library.
    public let source: FCCaptureSource

    /// Where the device was when recording started, when the host opted into
    /// location via `capturesLocation` and a fix was available. `nil` when
    /// location is off, denied, or the fix failed — a missing fix never blocks
    /// a capture.
    public let location: CLLocation?

    /// When recording started. For a gallery import this is the time of the
    /// import, not the asset's original creation date.
    public let capturedAt: Date

    public init(
        fileURL: URL,
        category: FCCategory?,
        duration: TimeInterval,
        thumbnail: UIImage?,
        source: FCCaptureSource,
        location: CLLocation? = nil,
        capturedAt: Date = Date()
    ) {
        self.fileURL = fileURL
        self.category = category
        self.duration = duration
        self.thumbnail = thumbnail
        self.source = source
        self.location = location
        self.capturedAt = capturedAt
    }
}
