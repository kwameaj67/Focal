//
//  MediaPermissions.swift
//  PurpleWaveCameraCore
//
//  Thin async wrappers around the authorizations the SDK needs. Camera and
//  photo library live here; the microphone accessors live in
//  PurpleWaveCameraVideo.
//
//  Core still names the microphone as a `PWPermission` case, and
//  `PermissionDeniedView` has copy for it, but it makes no microphone API call
//  anywhere — no `AVCaptureDevice` audio query, request, or input. That's the
//  part that matters: a host linking only PurpleWaveCameraPhoto needs no
//  NSMicrophoneUsageDescription and discloses no microphone access.
//
//  IMPORTANT: The host app must declare the matching usage-description keys in
//  its Info.plist or the app will crash when access is requested:
//    • NSCameraUsageDescription
//    • NSPhotoLibraryUsageDescription      (gallery import)
//    • NSPhotoLibraryAddUsageDescription   (save-to-album)
//    • NSMicrophoneUsageDescription        (only if you link
//                                           PurpleWaveCameraVideo)
//

import AVFoundation
import Photos
import UIKit

/// The distinct permissions the SDK may request.
public enum PWPermission: Sendable {
    case camera
    case microphone
    case photoLibrary
    case location
}

/// A normalized authorization status shared across the three systems.
public enum PWPermissionStatus: Sendable {
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
    public static func cameraStatus() -> PWPermissionStatus {
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
    ) -> PWPermissionStatus {
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

    /// Ensures every permission required by a *photo* flow is granted.
    /// - Parameter needsLibrary: pass the value of `config.allowsGallery ||
    ///   config.savesToPhotoLibrary`.
    /// - Returns: `nil` on success, or the first denied permission.
    public static func ensurePhotoPermissions(
        needsLibrary: Bool
    ) async -> PWPermission? {
        if !(await requestCamera()) { return .camera }
        if needsLibrary, !(await requestPhotoLibrary()) { return .photoLibrary }
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

    /// `package` so the microphone accessors in PurpleWaveCameraVideo can
    /// reuse the same normalization. Not public: hosts get the mapped
    /// `PWPermissionStatus` values, never the AVFoundation ones.
    package static func map(_ status: AVAuthorizationStatus) -> PWPermissionStatus {
        switch status {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PWPermissionStatus {
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
