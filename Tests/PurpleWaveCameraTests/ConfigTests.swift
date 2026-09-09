//
//  ConfigTests.swift
//  PurpleWaveCameraTests
//
//  Covers category resolution, per-category preset lookup, and the enum
//  bridges to AVFoundation.
//

import XCTest
import AVFoundation
@testable import PurpleWaveCameraCore
@testable import PurpleWaveCameraPhoto
@testable import PurpleWaveCameraVideo

final class ConfigTests: XCTestCase {

    private let categories = [
        PWCategory(id: "AMKT", title: "Profile"),
        PWCategory(id: "STICKER", title: "Sticker"),
        PWCategory(id: "WALK", title: "Walk Around")
    ]

    // MARK: - PWCameraConfig.initialCategory

    func testPhotoInitialCategoryIsNilWhenNoCategories() {
        XCTAssertNil(PWCameraConfig().initialCategory)
    }

    func testPhotoInitialCategoryFallsBackToFirst() {
        let config = PWCameraConfig(categories: categories)
        XCTAssertEqual(config.initialCategory?.id, "AMKT")
    }

    func testPhotoInitialCategoryHonorsStartingID() {
        let config = PWCameraConfig(categories: categories, startingCategoryID: "WALK")
        XCTAssertEqual(config.initialCategory?.id, "WALK")
    }

    func testPhotoInitialCategoryFallsBackWhenStartingIDMissing() {
        let config = PWCameraConfig(categories: categories, startingCategoryID: "NOPE")
        XCTAssertEqual(config.initialCategory?.id, "AMKT")
    }

    // MARK: - PWVideoConfig.initialCategory

    func testVideoInitialCategoryHonorsStartingID() {
        let config = PWVideoConfig(categories: categories, startingCategoryID: "STICKER")
        XCTAssertEqual(config.initialCategory?.id, "STICKER")
    }

    // MARK: - PWVideoConfig.preset(for:)

    func testPresetUsesPerCategoryOverride() {
        let config = PWVideoConfig(
            categories: categories,
            presetByCategoryID: ["AMKT": .hd1080],
            defaultPreset: .hd720
        )
        XCTAssertEqual(config.preset(for: PWCategory(id: "AMKT", title: "x")).avPreset,
                       AVCaptureSession.Preset.hd1920x1080)
    }

    func testPresetFallsBackToDefaultForUnlistedCategory() {
        let config = PWVideoConfig(
            categories: categories,
            presetByCategoryID: ["AMKT": .hd1080],
            defaultPreset: .hd720
        )
        XCTAssertEqual(config.preset(for: PWCategory(id: "WALK", title: "x")).avPreset,
                       AVCaptureSession.Preset.hd1280x720)
    }

    func testPresetFallsBackToDefaultForNilCategory() {
        let config = PWVideoConfig(defaultPreset: .hd720)
        XCTAssertEqual(config.preset(for: nil).avPreset, AVCaptureSession.Preset.hd1280x720)
    }

    // MARK: - Enum bridges

    func testFlashModeBridging() {
        XCTAssertEqual(PWFlashMode.auto.avFlashMode, .auto)
        XCTAssertEqual(PWFlashMode.on.avFlashMode, .on)
        XCTAssertEqual(PWFlashMode.off.avFlashMode, .off)
    }

    func testVideoQualityBridging() {
        XCTAssertEqual(PWVideoQuality.hd1080.avPreset, .hd1920x1080)
        XCTAssertEqual(PWVideoQuality.hd720.avPreset, .hd1280x720)
    }
}
