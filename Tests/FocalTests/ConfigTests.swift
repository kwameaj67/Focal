//
//  ConfigTests.swift
//  FocalTests
//
//  Covers category resolution, per-category preset lookup, and the enum
//  bridges to AVFoundation.
//

import XCTest
import AVFoundation
@testable import FocalCore
@testable import FocalPhoto
@testable import FocalVideo

final class ConfigTests: XCTestCase {

    private let categories = [
        FCCategory(id: "AMKT", title: "Profile"),
        FCCategory(id: "STICKER", title: "Sticker"),
        FCCategory(id: "WALK", title: "Walk Around")
    ]

    // MARK: - FCCameraConfig.initialCategory

    func testPhotoInitialCategoryIsNilWhenNoCategories() {
        XCTAssertNil(FCCameraConfig().initialCategory)
    }

    func testPhotoInitialCategoryFallsBackToFirst() {
        let config = FCCameraConfig(categories: categories)
        XCTAssertEqual(config.initialCategory?.id, "AMKT")
    }

    func testPhotoInitialCategoryHonorsStartingID() {
        let config = FCCameraConfig(categories: categories, startingCategoryID: "WALK")
        XCTAssertEqual(config.initialCategory?.id, "WALK")
    }

    func testPhotoInitialCategoryFallsBackWhenStartingIDMissing() {
        let config = FCCameraConfig(categories: categories, startingCategoryID: "NOPE")
        XCTAssertEqual(config.initialCategory?.id, "AMKT")
    }

    // MARK: - FCVideoConfig.initialCategory

    func testVideoInitialCategoryHonorsStartingID() {
        let config = FCVideoConfig(categories: categories, startingCategoryID: "STICKER")
        XCTAssertEqual(config.initialCategory?.id, "STICKER")
    }

    // MARK: - FCVideoConfig.preset(for:)

    func testPresetUsesPerCategoryOverride() {
        let config = FCVideoConfig(
            categories: categories,
            presetByCategoryID: ["AMKT": .hd1080],
            defaultPreset: .hd720
        )
        XCTAssertEqual(config.preset(for: FCCategory(id: "AMKT", title: "x")).avPreset,
                       AVCaptureSession.Preset.hd1920x1080)
    }

    func testPresetFallsBackToDefaultForUnlistedCategory() {
        let config = FCVideoConfig(
            categories: categories,
            presetByCategoryID: ["AMKT": .hd1080],
            defaultPreset: .hd720
        )
        XCTAssertEqual(config.preset(for: FCCategory(id: "WALK", title: "x")).avPreset,
                       AVCaptureSession.Preset.hd1280x720)
    }

    func testPresetFallsBackToDefaultForNilCategory() {
        let config = FCVideoConfig(defaultPreset: .hd720)
        XCTAssertEqual(config.preset(for: nil).avPreset, AVCaptureSession.Preset.hd1280x720)
    }

    // MARK: - Enum bridges

    func testFlashModeBridging() {
        XCTAssertEqual(FCFlashMode.auto.avFlashMode, .auto)
        XCTAssertEqual(FCFlashMode.on.avFlashMode, .on)
        XCTAssertEqual(FCFlashMode.off.avFlashMode, .off)
    }

    func testVideoQualityBridging() {
        XCTAssertEqual(FCVideoQuality.hd1080.avPreset, .hd1920x1080)
        XCTAssertEqual(FCVideoQuality.hd720.avPreset, .hd1280x720)
    }
}
