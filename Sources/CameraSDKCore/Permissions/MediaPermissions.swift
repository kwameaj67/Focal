//
//  MediaPermissions.swift
//  CameraSDKCore
//
//  Thin async wrappers around the authorizations the SDK needs. Camera and
//  photo library live here; the microphone accessors live in
//  CameraSDKVideo.
//
//  Core still names the microphone as a `CSPermission` case, and
//  `PermissionDeniedView` has copy for it, but it makes no microphone API call
//  anywhere — no `AVCaptureDevice` audio query, request, or input. That's the
//  part that matters: a host linking only CameraSDKPhoto needs no
//  NSMicrophoneUsageDescription and discloses no microphone access.
//
//  IMPORTANT: The host app must declare the matching usage-description keys in
//  its Info.plist or the app will crash when access is requested:
//    • NSCameraUsageDescription
//    • NSPhotoLibraryUsageDescription      (gallery import)
//    • NSPhotoLibraryAddUsageDescription   (save-to-album)
//    • NSMicrophoneUsageDescription        (only if you link
//                                           CameraSDKVideo)
//

import AVFoundation
import Photos
import UIKit

/// The distinct permissions the SDK may request.
public enum CSPermission: Sendable {
    case camera
    case microphone
    case photoLibrary
    case location
}

/// A normalized authorization status shared across the three systems.
public enum CSPermissionStatus: Sendable {
    case granted
    /// Includes `.limited` photo-library access, which is usable for our needs.
    case limited
    case denied
    case restricted
    case notDetermined
}

/// Namespace for permission checks and requests. All request methods are
/// `async` and safe to call from the main actor.
public enum MediaPermissions {

    // MARK: Camera

    /// Current camera authorization without prompting.
    public static func cameraStatus() -> CSPermissionStatus {
        map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Requests camera access, returning `true` if granted.
    @discardableResult
    public static func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: Photo library

    /// Current photo-library authorization for the given access level.
    public static func photoLibraryStatus(
        for level: PHAccessLevel = .readWrite
    ) -> CSPermissionStatus {
        map(PHPhotoLibrary.authorizationStatus(for: level))
    }

    /// Requests photo-library access. `.limited` counts as usable and returns
    /// `true`.
    @discardableResult
    public static func requestPhotoLibrary(
        for level: PHAccessLevel = .readWrite
    ) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: level)
        switch status {
        case .authorized, .limited: return true
        default: return false
        }
    }

    // MARK: Convenience

    /// Requests add-only photo-library access, for saving captures.
    ///
    /// Separate from `requestPhotoLibrary()` because the two are genuinely
    /// different asks: reading the library to import needs `.readWrite`, while
    /// writing a capture into an album needs only `.addOnly` — a much smaller
    /// permission that iOS presents differently and that many users will grant
    /// when they would refuse full access.
    @discardableResult
    public static func requestPhotoLibraryAdd() async -> Bool {
        await requestPhotoLibrary(for: .addOnly)
    }

    /// Ensures the permissions a photo capture screen cannot start without.
    ///
    /// Camera only. Photo-library access is deliberately not requested here:
    /// reading the library is asked for when the gallery is opened, and adding
    /// to it when a capture is actually saved. Bundling them meant declining
    /// the library took down the whole capture screen, even though the camera
    /// worked fine.
    ///
    /// - Returns: `nil` on success, or the denied permission.
    public static func ensurePhotoPermissions() async -> CSPermission? {
        if !(await requestCamera()) { return .camera }
        return nil
    }

    /// Opens the host app's Settings page so the user can flip a denied
    /// permission. Call from the main actor.
    @MainActor
    public static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Mapping helpers

    /// `package` so the microphone accessors in CameraSDKVideo can
    /// reuse the same normalization. Not public: hosts get the mapped
    /// `CSPermissionStatus` values, never the AVFoundation ones.
    package static func map(_ status: AVAuthorizationStatus) -> CSPermissionStatus {
        switch status {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> CSPermissionStatus {
        switch status {
        case .authorized:    return .granted
        case .limited:       return .limited
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }
}
