//
//  DeviceOrientationMonitor.swift
//  FocalCore
//
//  Publishes the physical device orientation using the accelerometer (via
//  CoreMotion) rather than `UIDevice.orientation`. This keeps working even when
//  the app's UI orientation is locked — which is exactly what a camera needs so
//  that overlays and capture orientation follow how the phone is actually held.
//

import AVFoundation
import Combine
import CoreMotion
import UIKit

/// Observable source of truth for how the device is being held.
package final class DeviceOrientationMonitor: ObservableObject {

    /// The latest interface-relevant orientation. Face-up/face-down/unknown are
    /// filtered out so consumers only ever see portrait / landscape values.
    @Published package private(set) var orientation: UIDeviceOrientation = .portrait

    /// The orientation expressed as a rotation angle (radians), handy for
    /// rotating overlay controls to stay upright.
    @Published package private(set) var angle: Double = 0

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.focal.camera.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    /// Starts delivering orientation updates. Safe to call repeatedly.
    package init() {}

    package func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.2

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            guard let newOrientation = Self.orientation(from: gravity),
                  newOrientation != self.orientation else { return }

            DispatchQueue.main.async {
                self.orientation = newOrientation
                self.angle = Self.angle(for: newOrientation)
            }
        }
    }

    /// Stops delivering updates. Call from `onDisappear` / `deinit`.
    package func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    deinit { stop() }

    // MARK: - Math
    // These are `internal static` (not `private`) purely so unit tests can
    // exercise the orientation math without a device — they are not part of the
    // public API.

    /// Derives a `UIDeviceOrientation` from a gravity vector. Returns `nil` for
    /// ambiguous (mostly flat) positions so we keep the last stable value.
    package static func orientation(from gravity: CMAcceleration) -> UIDeviceOrientation? {
        let threshold = 0.75
        if gravity.x >= threshold { return .landscapeRight }
        if gravity.x <= -threshold { return .landscapeLeft }
        if gravity.y <= -threshold { return .portrait }
        if gravity.y >= threshold { return .portraitUpsideDown }
        return nil
    }

    /// Rotation (radians) that keeps a control upright for the given orientation.
    package static func angle(for orientation: UIDeviceOrientation) -> Double {
        switch orientation {
        case .portrait:           return 0
        case .portraitUpsideDown: return .pi
        case .landscapeLeft:      return 0.5 * .pi
        case .landscapeRight:     return -0.5 * .pi
        default:                  return 0
        }
    }
}

package extension UIDeviceOrientation {
    /// `true` for either landscape orientation.
    var fcIsLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }

    /// Capture rotation for this device orientation, in degrees, for
    /// `AVCaptureConnection.videoRotationAngle`.
    ///
    /// Replaces the deprecated `AVCaptureVideoOrientation` bridge. The angles
    /// correspond to the old cases exactly — `landscapeRight` is 0°, `portrait`
    /// 90°, `landscapeLeft` 180°, `portraitUpsideDown` 270° — so behaviour is
    /// unchanged, including the left/right swap: a device held `.landscapeLeft`
    /// needs the `.landscapeRight` capture rotation for the frame to come out
    /// upright.
    var fcCaptureRotationAngle: CGFloat {
        switch self {
        case .portraitUpsideDown: return 270   // was .portraitUpsideDown
        case .landscapeLeft:      return 0     // was .landscapeRight
        case .landscapeRight:     return 180   // was .landscapeLeft
        default:                  return 90    // was .portrait
        }
    }
}

package extension AVCaptureConnection {

    /// Sets `videoRotationAngle`, ignoring angles the connection doesn't
    /// support.
    ///
    /// Unlike the old `videoOrientation`, this property has a support query and
    /// assigning an unsupported value is an error rather than a no-op, so the
    /// check isn't optional.
    func fcSetRotationAngle(_ angle: CGFloat) {
        guard isVideoRotationAngleSupported(angle) else { return }
        videoRotationAngle = angle
    }
}
