//
//  ConfigTests.swift
//  CameraSDKTests
//
//  Covers category resolution, per-category preset lookup, and the enum
//  bridges to AVFoundation.
//

import XCTest
import AVFoundation
@testable import CameraSDKCore
@testable import CameraSDKPhoto
@testable import CameraSDKVideo

final class ConfigTests: XCTestCase {

    private let categories = [
        CSCategory(id: "AMKT", title: "Profile"),
        CSCategory(id: "STICKER", title: "Sticker"),
        CSCategory(id: "WALK", title: "Walk Around")
    ]

    // MARK: - CSCameraConfig.initialCategory

    func testPhotoInitialCategoryIsNilWhenNoCategories() {
        XCTAssertNil(CSCameraConfig().initialCategory)
    }

    func testPhotoInitialCategoryFallsBackToFirst() {
        let config = CSCameraConfig(categories: categories)
        XCTAssertEqual(config.initialCategory?.id, "AMKT")
    }

    func testPhotoInitialCategoryHonorsStartingID() {
        let config = CSCameraConfig(categories: categories, startingCategoryID: "WALK")
        XCTAssertEqual(config.initialCategory?.id, "WALK")
    }

    func testPhotoInitialCategoryFallsBackWhenStartingIDMissing() {
        let config = CSCameraConfig(categories: categories, startingCategoryID: "NOPE")
        XCTAssertEqual(config.initialCategory?.id, "AMKT")
    }

    // MARK: - CSVideoConfig.initialCategory

    func testVideoInitialCategoryHonorsStartingID() {
        let config = CSVideoConfig(categories: categories, startingCategoryID: "STICKER")
        XCTAssertEqual(config.initialCategory?.id, "STICKER")
    }

    // MARK: - CSVideoConfig.preset(for:)

    func testPresetUsesPerCategoryOverride() {
        let config = CSVideoConfig(
            categories: categories,
            presetByCategoryID: ["AMKT": .hd1080],
            defaultPreset: .hd720
        )
        XCTAssertEqual(config.preset(for: CSCategory(id: "AMKT", title: "x")).avPreset,
                       AVCaptureSession.Preset.hd1920x1080)
    }

    func testPresetFallsBackToDefaultForUnlistedCategory() {
        let config = CSVideoConfig(
            categories: categories,
            presetByCategoryID: ["AMKT": .hd1080],
            defaultPreset: .hd720
        )
        XCTAssertEqual(config.preset(for: CSCategory(id: "WALK", title: "x")).avPreset,
                       AVCaptureSession.Preset.hd1280x720)
    }

    func testPresetFallsBackToDefaultForNilCategory() {
        let config = CSVideoConfig(defaultPreset: .hd720)
        XCTAssertEqual(config.preset(for: nil).avPreset, AVCaptureSession.Preset.hd1280x720)
    }

    // MARK: - Enum bridges

    func testFlashModeBridging() {
        XCTAssertEqual(CSFlashMode.auto.avFlashMode, .auto)
        XCTAssertEqual(CSFlashMode.on.avFlashMode, .on)
        XCTAssertEqual(CSFlashMode.off.avFlashMode, .off)
    }

    func testVideoQualityBridging() {
        XCTAssertEqual(CSVideoQuality.hd1080.avPreset, .hd1920x1080)
        XCTAssertEqual(CSVideoQuality.hd720.avPreset, .hd1280x720)
    }
}
