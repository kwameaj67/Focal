//
//  MediaImporter.swift
//  PurpleWaveCameraCore
//
//  Turns picked `PHAsset`s into the same result types the live capture path
//  produces: full-resolution image data for photos, and a local file copy for
//  videos.
//

import Photos
import UIKit
import AVFoundation

package enum MediaImporter {

    // MARK: - Photos

    /// Requests the full-resolution image for a photo asset and encodes it to
    /// JPEG data, returning both the data and a `UIImage`.
    package static func importImage(_ asset: PHAsset) async -> (data: Data, image: UIImage)? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current

        let image: UIImage? = await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                cont.resume(returning: result)
            }
        }

        guard let image, let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return (data, image)
    }

    // MARK: - Videos

    /// Copies a video asset's underlying file into `directory` and returns the
    /// new local URL plus its duration. Enforces `maxFileSizeMB`.
    package static func importVideo(
        _ asset: PHAsset,
        into directory: URL,
        maxFileSizeMB: Double
    ) async -> (url: URL, duration: TimeInterval)? {

        let options = PHVideoRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let urlAsset: AVURLAsset? = await withCheckedContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                cont.resume(returning: avAsset as? AVURLAsset)
            }
        }

        guard let urlAsset else { return nil }

        // Size guard.
        if let size = try? FileManager.default
            .attributesOfItem(atPath: urlAsset.url.path)[.size] as? UInt64 {
            let mb = Double(size) / (1024 * 1024)
            if mb > maxFileSizeMB { return nil }
        }

        let destination = directory.appendingPathComponent("\(UUID().uuidString).mov")
        do {
            try FileManager.default.copyItem(at: urlAsset.url, to: destination)
        } catch {
            return nil
        }

        let duration = (try? await urlAsset.load(.duration).seconds) ?? 0
        return (destination, duration)
    }

    /// Generates a first-frame thumbnail for a local video URL.
    package static func thumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        return await withCheckedContinuation { cont in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, _, _ in
                cont.resume(returning: image.map(UIImage.init))
            }
        }
    }
}
