//
//  LocationManager.swift
//  FocalCore
//
//  A one-shot location source for tagging captures. Both capture screens use
//  it, so it lives in Core alongside the other device services.
//
//  This is deliberately not a continuous tracker. Capture screens want "where
//  was the device when this photo was taken", which is a single fix at capture
//  time — not a stream of updates. Continuous updates would drain battery for
//  no benefit and keep the location indicator lit for the whole session.
//
//  IMPORTANT: location is opt-in per screen via `capturesLocation` on the
//  config. Nothing here runs unless a host asks for it, so a host that doesn't
//  want location never prompts for it and needs no usage description. Hosts
//  that do opt in must declare `NSLocationWhenInUseUsageDescription`, or the
//  app will crash when authorization is requested.
//

import CoreLocation

/// Wraps `CLLocationManager` to provide authorization and a single location fix.
///
/// `package` rather than public: the capture screens drive this, and hosts
/// receive the resulting `CLLocation` on the result type rather than talking to
/// it directly.
package final class LocationManager: NSObject, @unchecked Sendable {

    /// Shared instance. `CLLocationManager` is comparatively expensive to spin
    /// up, and authorization is process-wide, so one instance serves both
    /// screens.
    package static let shared = LocationManager()

    private let manager = CLLocationManager()

    /// Continuations waiting on the in-flight authorization prompt. More than
    /// one can queue up if a screen appears while another request is pending.
    private var authContinuations: [CheckedContinuation<Bool, Never>] = []

    /// Continuations waiting on the in-flight location fix, for the same reason.
    private var fixContinuations: [CheckedContinuation<CLLocation?, Never>] = []

    /// Guards both continuation arrays; callbacks arrive on the main queue but
    /// callers can be anywhere.
    private let lock = NSLock()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    // MARK: - Authorization

    /// Current authorization, without prompting.
    package var status: FCPermissionStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied:                                 return .denied
        case .restricted:                             return .restricted
        case .notDetermined:                          return .notDetermined
        @unknown default:                             return .denied
        }
    }

    /// Requests when-in-use access, returning `true` if usable.
    ///
    /// Returns immediately when the decision has already been made, so this is
    /// safe to call on every screen appearance.
    @discardableResult
    package func requestAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            authContinuations.append(continuation)
            let isFirst = authContinuations.count == 1
            lock.unlock()

            // Only one prompt: later callers ride on the same delegate callback.
            if isFirst {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    // MARK: - Location

    /// Returns a single location fix, or `nil` if location is unavailable,
    /// denied, or the fix fails.
    ///
    /// Never throws and never blocks a capture: a failed fix means the result
    /// simply carries no location. Losing GPS should not lose the photo.
    package func currentLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        guard await requestAuthorization() else { return nil }

        // A recent cached fix is good enough for tagging a capture and avoids
        // waiting on the radio.
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -30 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            fixContinuations.append(continuation)
            let isFirst = fixContinuations.count == 1
            lock.unlock()

            if isFirst {
                manager.requestLocation()
            }
        }
    }

    // MARK: - Continuation plumbing

    private func resumeAuth(_ granted: Bool) {
        lock.lock()
        let waiting = authContinuations
        authContinuations.removeAll()
        lock.unlock()
        waiting.forEach { $0.resume(returning: granted) }
    }

    private func resumeFix(_ location: CLLocation?) {
        lock.lock()
        let waiting = fixContinuations
        fixContinuations.removeAll()
        lock.unlock()
        waiting.forEach { $0.resume(returning: location) }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    package func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            return   // still waiting on the user
        case .authorizedAlways, .authorizedWhenInUse:
            resumeAuth(true)
        default:
            resumeAuth(false)
            // Anything waiting on a fix will never get one now.
            resumeFix(nil)
        }
    }

    package func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        resumeFix(locations.last)
    }

    package func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        resumeFix(nil)
    }
}
