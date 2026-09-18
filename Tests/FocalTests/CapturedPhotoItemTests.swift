//
//  CapturedPhotoItemTests.swift
//  FocalTests
//
//  A 30-shot session used to hold thirty decoded 12MP bitmaps — around 1.4 GB,
//  well past the point where iOS jetsams the app. The fix was to keep only the
//  encoded bytes plus a thumbnail, and decode full-size on demand.
//
//  These tests pin the two properties that fix depends on: the retained
//  thumbnail is small, and the encoded bytes still decode to the original.
//

import XCTest
import UIKit
@testable import FocalPhoto

final class CapturedPhotoItemTests: XCTestCase {

    /// Roughly a 12MP frame — the size a modern rear camera actually delivers.
    private func makeLargeImage() -> UIImage {
        let size = CGSize(width: 4032, height: 3024)
        let format = UIGraphicsImageRendererFormat()
        // Without this the renderer uses the screen scale and produces a
        // 109MP image, which measures the test rig rather than the SDK.
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testThumbnailIsDownscaledFromALargeImage() throws {
        let large = makeLargeImage()
        let data = try XCTUnwrap(large.jpegData(compressionQuality: 0.9))

        let item = CapturedPhotoItem(data: data, image: large, category: nil)

        // The exact size is aspect-fitted, so assert the bound rather than a
        // specific dimension.
        XCTAssertLessThanOrEqual(item.thumbnail.size.width * item.thumbnail.scale, 400)
        XCTAssertLessThanOrEqual(item.thumbnail.size.height * item.thumbnail.scale, 400)
    }

    func testThumbnailCostsFarLessThanTheFullBitmap() throws {
        let large = makeLargeImage()
        let data = try XCTUnwrap(large.jpegData(compressionQuality: 0.9))

        let item = CapturedPhotoItem(data: data, image: large, category: nil)

        // 4 bytes per pixel, the layout a decoded bitmap actually occupies.
        func bitmapBytes(_ image: UIImage) -> Int {
            let px = image.size.width * image.scale * image.size.height * image.scale
            return Int(px) * 4
        }

        // The whole point of the change: what the item retains must be a tiny
        // fraction of what it used to. 12MP is ~48 MB; 400×400 is ~0.64 MB.
        XCTAssertLessThan(bitmapBytes(item.thumbnail) * 20, bitmapBytes(large))
    }

    func testEncodedDataStillDecodesToTheFullResolutionImage() throws {
        let large = makeLargeImage()
        let data = try XCTUnwrap(large.jpegData(compressionQuality: 0.9))

        let item = CapturedPhotoItem(data: data, image: large, category: nil)

        // The pager decodes from `data`, so the full-size image has to survive
        // the round trip — a thumbnail-only item would silently degrade the
        // preview.
        let decoded = try XCTUnwrap(UIImage(data: item.data))
        XCTAssertEqual(decoded.size.width * decoded.scale, 4032, accuracy: 1)
        XCTAssertEqual(decoded.size.height * decoded.scale, 3024, accuracy: 1)
    }
}
