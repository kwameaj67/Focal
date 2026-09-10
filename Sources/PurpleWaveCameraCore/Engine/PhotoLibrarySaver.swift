//
//  PhotoLibrarySaver.swift
//  PurpleWaveCameraCore
//
//  Optional helper for persisting captured media into a named album in the
//  system photo library. Only used when the host opts in via
//  `savesToPhotoLibrary`. Requires `NSPhotoLibraryAddUsageDescription`.
//

import Photos
import UIKit

package enum PhotoLibrarySaver {

    /// The album the SDK writes into when saving is enabled.
    package static let albumName = "FTCamera"

    /// Saves image data to the library album. Best-effort; failures are ignored.
    package static func save(imageData: Data) {
        guard hasAddPermission else { return }
        performInAlbum { request, placeholderOut in
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: .photo, data: imageData, options: nil)
            placeholderOut(creation.placeholderForCreatedAsset)
        }
    }

    /// Saves a video file to the library album. Best-effort.
    package static func save(videoURL: URL) {
        guard hasAddPermission,
              FileManager.default.fileExists(atPath: videoURL.path) else { return }
        performInAlbum { request, placeholderOut in
            guard let creation = PHAssetChangeRequest
                .creationRequestForAssetFromVideo(atFileURL: videoURL) else { return }
            placeholderOut(creation.placeholderForCreatedAsset)
        }
    }

    // MARK: - Internals

    private static var hasAddPermission: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }

    /// Asks for add-only access if it hasn't been decided yet, then reports
    /// whether saving is possible.
    ///
    /// Requested here rather than when the screen appears: a host that never
    /// captures anything shouldn't be prompted, and a prompt at the moment of
    /// saving is one the user can connect to something they just did.
    package static func ensureAddPermission() async -> Bool {
        if hasAddPermission { return true }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined else {
            return false
        }
        return await MediaPermissions.requestPhotoLibraryAdd()
    }

    /// Ensures the album exists, then runs `body` to create an asset and add it.
    private static func performInAlbum(
        _ body: @escaping (_ albumRequest: PHAssetCollectionChangeRequest?,
                           _ placeholderOut: (PHObjectPlaceholder?) -> Void) -> Void
    ) {
        fetchOrCreateAlbum { collection in
            guard let collection else { return }
            PHPhotoLibrary.shared().performChanges({
                var placeholder: PHObjectPlaceholder?
                body(nil) { placeholder = $0 }
                if let placeholder,
                   let albumChange = PHAssetCollectionChangeRequest(for: collection) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }, completionHandler: nil)
        }
    }

    private static func fetchOrCreateAlbum(
        completion: @escaping (PHAssetCollection?) -> Void
    ) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: options
        )
        if let album = existing.firstObject {
            completion(album)
            return
        }

        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: albumName)
            placeholder = request.placeholderForCreatedAssetCollection
        }, completionHandler: { success, _ in
            guard success, let id = placeholder?.localIdentifier else {
                completion(nil)
                return
            }
            let created = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [id], options: nil
            )
            completion(created.firstObject)
        })
    }
}
