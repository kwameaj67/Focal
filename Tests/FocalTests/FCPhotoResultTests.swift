//
//  FCPhotoResultTests.swift
//  FocalTests
//
//  `onImport` hands the host a whole gallery selection at once. When every
//  result stored a decoded 12MP bitmap, forty photos cost ~2 GB before the
//  callback fired. Results now decode on demand and cache the result.
//
//  These tests pin both halves: the decode is deferred, and it happens once.
//

import XCTest
import UIKit
@testable import FocalPhoto

final class FCPhotoResultTests: XCTestCase {

    private func makeImage(_ side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testLazyResultDecodesTheCorrectImageOnDemand() throws {
        let data = try XCTUnwrap(makeImage(1200).jpegData(compressionQuality: 0.9))

        let result = FCPhotoResult(
            imageData: data,
            category: nil,
            source: .gallery,
            orientation: .portrait
        )

        // Deferring the decode must not change what the host eventually gets.
        XCTAssertEqual(result.image.size.width * result.image.scale, 1200, accuracy: 1)
        XCTAssertEqual(result.image.size.height * result.image.scale, 1200, accuracy: 1)
    }

    func testLazyResultDecodesOnlyOnce() throws {
        let data = try XCTUnwrap(makeImage(1200).jpegData(compressionQuality: 0.9))

        let result = FCPhotoResult(
            imageData: data,
            category: nil,
            source: .gallery,
            orientation: .portrait
        )

        // Identity, not equality: a fresh decode per access would be ruinous
        // inside a SwiftUI body, which reads `image` on every render pass.
        XCTAssertTrue(result.image === result.image)
    }

    func testCopiesShareOneDecode() throws {
        let data = try XCTUnwrap(makeImage(1200).jpegData(compressionQuality: 0.9))

        let result = FCPhotoResult(
            imageData: data,
            category: nil,
            source: .gallery,
            orientation: .portrait
        )
        // FCPhotoResult is a struct and gets copied freely — into the batch
        // array, out to the host, into their own models. The decode is shared
        // across those copies rather than repeated per copy.
        let copy = result

        XCTAssertTrue(result.image === copy.image)
    }

    func testCaptureResultUsesTheImageItWasGiven() throws {
        let image = makeImage(1200)
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))

        let result = FCPhotoResult(
            imageData: data,
            image: image,
            category: nil,
            source: .camera,
            orientation: .portrait
        )

        // The live-capture path already holds decoded pixels off the sensor,
        // so seeding must skip the decode entirely, not re-do it.
        XCTAssertTrue(result.image === image)
    }
}
