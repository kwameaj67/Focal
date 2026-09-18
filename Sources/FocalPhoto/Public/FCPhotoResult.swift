//
//  FCPhotoResult.swift
//  FocalPhoto
//
//  What the host receives for a single captured or imported photo.
//

import UIKit
import CoreLocation
import FocalCore

/// The result of a single photo capture (or a single gallery import).
public struct FCPhotoResult {

    /// Encoded image data (HEVC/JPEG depending on device support), suitable for
    /// writing to disk or uploading.
    public let imageData: Data

    /// A ready-to-display `UIImage` decoded from `imageData`.
    ///
    /// Decoded on first access and held from then on, so reading it repeatedly
    /// — inside a SwiftUI `body`, say — costs nothing after the first time.
    ///
    /// The laziness matters for batch imports: `onImport` hands over the whole
    /// selection at once, and a decoded 12MP frame is ~47 MB. Decoding eagerly
    /// meant a forty-photo selection cost ~2 GB before the callback even fired.
    /// Now the results carry only their encoded bytes until something asks for
    /// pixels, so a host that uploads and discards one at a time never pays for
    /// more than one.
    public var image: UIImage { storage.resolve(from: imageData) }

    private let storage: LazyImage

    /// The category selected in the scroll bar when this photo was taken.
    /// `nil` if the host configured no categories.
    public let category: FCCategory?

    /// Whether the photo was captured live or imported from the library.
    public let source: FCCaptureSource

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

    /// Builds a result from bytes plus the image already decoded from them.
    ///
    /// Use this when a decoded image is in hand anyway — a live capture, where
    /// the pixels came off the sensor — so `image` costs nothing to read.
    public init(
        imageData: Data,
        image: UIImage,
        category: FCCategory?,
        source: FCCaptureSource,
        orientation: UIDeviceOrientation,
        metadata: [String: Any]? = nil,
        location: CLLocation? = nil,
        capturedAt: Date = Date()
    ) {
        self.init(imageData: imageData,
                  decodedImage: image,
                  category: category,
                  source: source,
                  orientation: orientation,
                  metadata: metadata,
                  location: location,
                  capturedAt: capturedAt)
    }

    /// Builds a result that decodes its image only if the host asks for it.
    ///
    /// Internal because it is only correct where the encoded bytes are known to
    /// be a decodable image — currently the gallery import, whose data comes
    /// straight from Photos.
    init(
        imageData: Data,
        category: FCCategory?,
        source: FCCaptureSource,
        orientation: UIDeviceOrientation,
        metadata: [String: Any]? = nil,
        location: CLLocation? = nil,
        capturedAt: Date = Date()
    ) {
        self.init(imageData: imageData,
                  decodedImage: nil,
                  category: category,
                  source: source,
                  orientation: orientation,
                  metadata: metadata,
                  location: location,
                  capturedAt: capturedAt)
    }

    private init(
        imageData: Data,
        decodedImage: UIImage?,
        category: FCCategory?,
        source: FCCaptureSource,
        orientation: UIDeviceOrientation,
        metadata: [String: Any]?,
        location: CLLocation?,
        capturedAt: Date
    ) {
        self.imageData = imageData
        self.storage = LazyImage(decodedImage)
        self.category = category
        self.source = source
        self.orientation = orientation
        self.metadata = metadata
        self.location = location
        self.capturedAt = capturedAt
    }
}

// MARK: - Deferred decode

/// Holds the decoded form of a result's `imageData`, decoding on first demand.
///
/// A reference type on purpose. `FCPhotoResult` is a struct that gets copied
/// freely, and the decode must happen at most once across every copy — a plain
/// computed property would re-decode on each access, which inside a SwiftUI
/// `body` would be far worse than the eager storage this replaces.
private final class LazyImage: @unchecked Sendable {

    private let lock = NSLock()
    private var cached: UIImage?

    /// `seed` is the already-decoded image, when the caller had one.
    init(_ seed: UIImage?) {
        cached = seed
    }

    func resolve(from data: Data) -> UIImage {
        lock.lock()
        defer { lock.unlock() }

        if let cached { return cached }

        // The empty fallback is unreachable in practice: every result is built
        // either from bytes the SDK just encoded or from an asset Photos just
        // decoded. Returning a blank image beats trapping in a host's view.
        let image = UIImage(data: data) ?? UIImage()
        cached = image
        return image
    }
}
