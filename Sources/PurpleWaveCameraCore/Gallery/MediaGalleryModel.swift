//
//  MediaGalleryModel.swift
//  PurpleWaveCameraCore
//

import Photos
import SwiftUI

package enum GalleryMediaType {
    case image
    case video

    package var phMediaType: PHAssetMediaType {
        switch self {
        case .image: return .image
        case .video: return .video
        }
    }

    package var pluralNoun: String {
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

    package let mediaType: GalleryMediaType

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    package init(mediaType: GalleryMediaType) {
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
            guard let created = asset.creationDate else { return }
            let day = calendar.startOfDay(for: created)
            buckets[day, default: []].append(asset)
        }

        return buckets
            .map { GallerySection(id: $0.key, title: headerFormatter.string(from: $0.key), assets: $0.value) }
            .sorted { $0.id > $1.id }   // newest day first
    }
}
