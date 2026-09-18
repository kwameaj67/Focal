//
//  ImageCropper.swift
//  FocalCore
//
//  Centre-crops a captured photo to a chosen aspect ratio.
//
//  The sensor delivers 4:3, so 16:9 and 1:1 are produced by discarding pixels
//  from the native frame. That is lossy and deliberate: the user framed the
//  shot in that ratio, so the file should match what they saw.
//

import UIKit

package enum ImageCropper {

    /// Centre-crops `image` to `ratio`, matching the image's own orientation.
    ///
    /// Returns the original untouched when it already matches, when the ratio
    /// is `.fourThree` (the native shape), or if anything goes wrong — a failed
    /// crop must never lose the capture.
    package static func crop(_ image: UIImage, to ratio: FCAspectRatio) -> UIImage {
        guard ratio.croppedFromSensor else { return image }
        guard let cgImage = image.cgImage else { return image }

        // Work in the CGImage's own pixel space, then hand the orientation back
        // untouched so EXIF-rotated captures aren't flipped by the crop.
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let target = ratio.ratio(isLandscape: width >= height)

        let current = width / height
        guard abs(current - target) > 0.001 else { return image }

        let cropWidth: CGFloat
        let cropHeight: CGFloat
        if current > target {
            // Too wide: trim the sides.
            cropHeight = height
            cropWidth = (height * target).rounded(.down)
        } else {
            // Too tall: trim top and bottom.
            cropWidth = width
            cropHeight = (width / target).rounded(.down)
        }

        let rect = CGRect(
            x: ((width - cropWidth) / 2).rounded(.down),
            y: ((height - cropHeight) / 2).rounded(.down),
            width: cropWidth,
            height: cropHeight
        )

        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Re-encodes a cropped image to JPEG so the returned `imageData` matches
    /// the returned `image`.
    ///
    /// Note this loses the original HEVC encoding and any EXIF the capture
    /// carried — the metadata dictionary is still delivered separately on the
    /// result, so nothing is lost outright, but a host writing `imageData`
    /// straight to disk gets JPEG rather than HEVC for cropped ratios.
    package static func encode(_ image: UIImage, quality: CGFloat = 0.95) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}
