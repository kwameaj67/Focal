//
//  MediaGalleryModel.swift
//  FocalCore
//

import Photos
import SwiftUI

/// Photos-framework bridging for the package's shared `MediaType`.
///
/// The type itself lives in `MediaType.swift`, kept framework-free; these two
/// members stay here because that type deliberately doesn't import Photos.
/// `prettyPrint` on the enum is the singular machine-ish form ("image");
/// `pluralNoun` is the human phrasing this UI needs ("photos"), so they're
/// separate rather than one doing both.
package extension MediaType {

    var phMediaType: PHAssetMediaType {
        switch self {
        case .image: return .image
        case .video: return .video
        }
    }

    var pluralNoun: String {
        switch self {
        case .image: return "photos"
        case .video: return "videos"
        }
    }
}

/// One day-grouped section of assets.
package struct GallerySection: Identifiable {
    package let id: Date          // start-of-day, also the identity
    package let title: String     // formatted date header
    package var assets: [PHAsset]
}

@MainActor
package final class MediaGalleryModel: ObservableObject {

    @Published package private(set) var sections: [GallerySection] = []
    @Published package var selected: [PHAsset] = []

    package let mediaType: MediaType

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    package init(mediaType: MediaType) {
        self.mediaType = mediaType
    }

    /// Loads assets from the library, assuming authorization was already
    /// granted by the presenting screen.
    package func load() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: mediaType.phMediaType, options: options)
        sections = Self.group(result)
    }

    /// Whether the library genuinely holds nothing of this media type, as
    /// opposed to the grid simply not having loaded yet. The screen needs the
    /// distinction to avoid flashing an empty state during the fetch.
    package var isEmpty: Bool { sections.isEmpty }

    /// Toggles selection for an asset.
    package func toggle(_ asset: PHAsset) {
        if let index = selected.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            selected.remove(at: index)
        } else {
            selected.append(asset)
        }
    }

    /// Whether the given asset is currently selected.
    package func isSelected(_ asset: PHAsset) -> Bool {
        selected.contains { $0.localIdentifier == asset.localIdentifier }
    }

    // MARK: - Grouping

    private static func group(_ result: PHFetchResult<PHAsset>) -> [GallerySection] {
        var buckets: [Date: [PHAsset]] = [:]
        let calendar = Calendar.current

        result.enumerateObjects { asset, _, _ in
            // An asset with no creation date used to be dropped here, which
            // silently hid it from the picker — the user could see it in Photos
            // and not here, with nothing to explain the difference. Fall back to
            // the modification date, and failing that bucket it under
            // `undatedDay` so it is still selectable.
            let date = asset.creationDate ?? asset.modificationDate
            let day = date.map(calendar.startOfDay(for:)) ?? undatedDay
            buckets[day, default: []].append(asset)
        }

        return buckets
            .map { GallerySection(id: $0.key, title: title(for: $0.key), assets: $0.value) }
            .sorted { $0.id > $1.id }   // newest day first, undated last
    }

    /// Sentinel bucket for assets carrying no usable date. `.distantPast` sorts
    /// it to the bottom, which is where an undated item belongs in a list
    /// ordered newest-first.
    private static let undatedDay = Date.distantPast

    private static func title(for day: Date) -> String {
        day == undatedDay ? "Unknown date" : headerFormatter.string(from: day)
    }
}
