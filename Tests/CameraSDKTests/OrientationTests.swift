//
//  OrientationTests.swift
//  CameraSDKTests
//
//  The orientation math is the highest-risk pure logic in the SDK — especially
//  the deliberate left/right swap when mapping device orientation to capture
//  orientation. These tests pin that behaviour down.
//

import XCTest
import AVFoundation
import CoreMotion
import UIKit
@testable import CameraSDKCore

final class OrientationTests: XCTestCase {

    // MARK: - Gravity → UIDeviceOrientation

    func testGravityMapsToPortrait() {
        let g = CMAcceleration(x: 0, y: -1, z: 0)
        XCTAssertEqual(DeviceOrientationMonitor.orientation(from: g), .portrait)
    }

    func testGravityMapsToPortraitUpsideDown() {
        let g = CMAcceleration(x: 0, y: 1, z: 0)
        XCTAssertEqual(DeviceOrientationMonitor.orientation(from: g), .portraitUpsideDown)
    }

    func testGravityMapsToLandscapeRight() {
        let g = CMAcceleration(x: 1, y: 0, z: 0)
        XCTAssertEqual(DeviceOrientationMonitor.orientation(from: g), .landscapeRight)
    }

    func testGravityMapsToLandscapeLeft() {
        let g = CMAcceleration(x: -1, y: 0, z: 0)
        XCTAssertEqual(DeviceOrientationMonitor.orientation(from: g), .landscapeLeft)
    }

    func testFlatGravityIsAmbiguousAndReturnsNil() {
        // Phone lying flat (mostly z), below the 0.75 threshold on x and y.
        let g = CMAcceleration(x: 0.1, y: 0.1, z: -0.98)
        XCTAssertNil(DeviceOrientationMonitor.orientation(from: g))
    }

    // MARK: - Upright rotation angle

    func testAngleForEachOrientation() {
        XCTAssertEqual(DeviceOrientationMonitor.angle(for: .portrait), 0, accuracy: 1e-9)
        XCTAssertEqual(DeviceOrientationMonitor.angle(for: .portraitUpsideDown), .pi, accuracy: 1e-9)
        XCTAssertEqual(DeviceOrientationMonitor.angle(for: .landscapeLeft), 0.5 * .pi, accuracy: 1e-9)
        XCTAssertEqual(DeviceOrientationMonitor.angle(for: .landscapeRight), -0.5 * .pi, accuracy: 1e-9)
    }

    // MARK: - UIDeviceOrientation helpers

    func testIsLandscape() {
        XCTAssertTrue(UIDeviceOrientation.landscapeLeft.csIsLandscape)
        XCTAssertTrue(UIDeviceOrientation.landscapeRight.csIsLandscape)
        XCTAssertFalse(UIDeviceOrientation.portrait.csIsLandscape)
        XCTAssertFalse(UIDeviceOrientation.faceUp.csIsLandscape)
    }

    func testCaptureOrientationSwapsLandscape() {
        // The key invariant: a device held landscape-left must record with a
        // landscape-right connection to come out upright, and vice versa.
        XCTAssertEqual(UIDeviceOrientation.landscapeLeft.csCaptureRotationAngle, 0)
        XCTAssertEqual(UIDeviceOrientation.landscapeRight.csCaptureRotationAngle, 180)
        XCTAssertEqual(UIDeviceOrientation.portrait.csCaptureRotationAngle, 90)
        XCTAssertEqual(UIDeviceOrientation.portraitUpsideDown.csCaptureRotationAngle, 270)
    }

    func testCaptureOrientationDefaultsToPortrait() {
        // Ambiguous physical orientations should not tilt the capture.
        XCTAssertEqual(UIDeviceOrientation.faceUp.csCaptureRotationAngle, 90)
        XCTAssertEqual(UIDeviceOrientation.faceDown.csCaptureRotationAngle, 90)
        XCTAssertEqual(UIDeviceOrientation.unknown.csCaptureRotationAngle, 90)
    }
}
