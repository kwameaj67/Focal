//
//  CSCamera.swift
//  CameraSDKCore
//
//  The UIKit factory namespace. It's declared here, in Core, so that each
//  capture target can hang its own factory method off it as an extension:
//  `makePhotoCapture` lives in CameraSDKPhoto and `makeVideoRecorder` in
//  CameraSDKVideo. A host that links only one of them sees only that
//  one's factory, which is the point of the split.
//

import UIKit

/// Namespace for creating capture screens as UIKit view controllers.
///
/// SwiftUI consumers don't need this — present `CSCameraScreen` or
/// `CSVideoScreen` directly.
public enum CSCamera {}

/// Holds a weak reference to a controller so wrapping closures can dismiss it
/// without creating a retain cycle.
///
/// `package` rather than `internal`: both factory extensions live in other
/// targets in this package, but this is plumbing and not something hosts should
/// see, so it stays out of the public API.
package final class ControllerHolder {
    package weak var controller: UIViewController?
    package init() {}
}
