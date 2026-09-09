//
//  OrientationTests.swift
//  PurpleWaveCameraTests
//
//  The orientation math is the highest-risk pure logic in the SDK — especially
//  the deliberate left/right swap when mapping device orientation to capture
//  orientation. These tests pin that behaviour down.
//

import XCTest
import AVFoundation
import CoreMotion
import UIKit
@testable import PurpleWaveCameraCore

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
        XCTAssertTrue(UIDeviceOrientation.landscapeLeft.pwIsLandscape)
        XCTAssertTrue(UIDeviceOrientation.landscapeRight.pwIsLandscape)
        XCTAssertFalse(UIDeviceOrientation.portrait.pwIsLandscape)
        XCTAssertFalse(UIDeviceOrientation.faceUp.pwIsLandscape)
    }

    func testCaptureOrientationSwapsLandscape() {
        // The key invariant: a device held landscape-left must record with a
        // landscape-right connection to come out upright, and vice versa.
        XCTAssertEqual(UIDeviceOrientation.landscapeLeft.pwCaptureVideoOrientation, .landscapeRight)
        XCTAssertEqual(UIDeviceOrientation.landscapeRight.pwCaptureVideoOrientation, .landscapeLeft)
        XCTAssertEqual(UIDeviceOrientation.portrait.pwCaptureVideoOrientation, .portrait)
        XCTAssertEqual(UIDeviceOrientation.portraitUpsideDown.pwCaptureVideoOrientation, .portraitUpsideDown)
    }

    func testCaptureOrientationDefaultsToPortrait() {
        // Ambiguous physical orientations should not tilt the capture.
        XCTAssertEqual(UIDeviceOrientation.faceUp.pwCaptureVideoOrientation, .portrait)
        XCTAssertEqual(UIDeviceOrientation.faceDown.pwCaptureVideoOrientation, .portrait)
        XCTAssertEqual(UIDeviceOrientation.unknown.pwCaptureVideoOrientation, .portrait)
    }
}
