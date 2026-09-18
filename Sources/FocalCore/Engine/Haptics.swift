//
//  Haptics.swift
//  FocalCore
//
//  Created by Kwame Agyenim - Boateng on 09/08/2026.
//


import Foundation
import UIKit
import CoreHaptics
import SwiftUI

package class HapticsManager {
    package static let shared = HapticsManager()
    
    private init(){}
    
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var engineNeedsStart = true
    private var foregroundToken: NSObjectProtocol?
    private var backgroundToken: NSObjectProtocol?
    lazy var supportsHaptics: Bool = {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }()

    // UIKit feedback generators back the discrete UI ticks below. Unlike
    // CHHapticEngine, they don't run through the app's audio session, so they
    // keep firing on the video screen — where the microphone's capture session
    // holds the audio session in a record category and interrupts (silences) the
    // haptic engine. That interrupt is exactly why every CHHapticEngine tick on
    // the recorder used to do nothing.
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    /// Primes the generators so the first tick has minimal latency.
    private func prepareGenerators() {
        impactLight.prepare()
        impactHeavy.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Feedback generators must be used on the main thread; some callers fire
    /// from background tasks (e.g. the record countdown), so hop if needed.
    private func onMain(_ body: @escaping () -> Void) {
        Thread.isMainThread ? body() : DispatchQueue.main.async(execute: body)
    }

    package func setupHapticEngine() {
        guard supportsHaptics else {
            print("[Haptic Engine]: Device does not support haptics.")
            return
        }

        // Prime the UIKit generators that actually drive the UI ticks.
        prepareGenerators()

        // Idempotent: if we already have a running engine, don't recreate it on
        // every screen appearance. The resetHandler sets `engineNeedsStart`, so
        // recreation still happens whenever the system tears the engine down.
        if engine != nil && !engineNeedsStart { return }

        do {
            engine = try CHHapticEngine()
        } catch {
            print("[Haptic Engine] Creation Error: \(error)")
        }
        
        // Handle when the engine stops unexpectedly
        engine?.stoppedHandler = { reason in
            print("Stop Handler: The engine stopped for reason: \(reason.rawValue)")
            switch reason {
            case .audioSessionInterrupt:
                print("Audio session interrupt")
            case .applicationSuspended:
                print("Application suspended")
            case .idleTimeout:
                print("Idle timeout")
            case .systemError:
                print("System error")
            case .notifyWhenFinished:
                print("Playback finished")
            case .gameControllerDisconnect:
                print("Controller disconnected.")
            case .engineDestroyed:
                print("Engine destroyed.")
            @unknown default:
                print("Unknown error")
            }
        }
        
        // Handle when the engine needs to reset
        engine?.resetHandler = { [weak self] in
            print("[Haptic Engine]: Resetting engine...")
            self?.setupHapticEngine()
            
            self?.engineNeedsStart = true
        }
        
        do {
            try engine?.start()
            print("[Haptic Engine]: Started successfully.")
            engineNeedsStart = false
        }
        catch {
            print("Failed to start the engine: \(error)")
        }
    }

    package func startContinuousHaptic() {
        guard let engine = engine else { return }
        
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0,
                duration: 0.3
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            player = try engine.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch let error as NSError{
            print("Failed to play continuous haptic: \(error.localizedDescription), Info: \(error.userInfo)")
        }
    }

    package func stopHaptic() {
        do {
            try player?.stop(atTime: 0)
            player = nil
            print("[Haptic Engine]: Stopped")
        } catch {
            print("Failed to stop haptic: \(error)")
        }
    }
    
    
    package func restartHapticEngine() {
        engine?.start { error in
            if let error = error {
                print("Haptic Engine Startup Error: \(error)")
                return
            }
            self.engineNeedsStart = false
        }
    }
    
    package func stopHapticEngine() {
        engine?.stop { error in
            if let error = error {
                print("Haptic Engine Shutdown Error: \(error)")
                return
            }
            self.engineNeedsStart = true
        }
    }
    
    package func addObservers() {
        // Idempotent: register the background/foreground observers only once so
        // repeated screen presentations don't leak duplicates.
        guard foregroundToken == nil, backgroundToken == nil else { return }

        backgroundToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                 object: nil,
                                                                 queue: nil) { [weak self] _ in
            guard let self = self, self.supportsHaptics else { return }
            
            self.stopHapticEngine()
        }

        foregroundToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                                 object: nil,
                                                                 queue: nil) { [weak self] _ in
            guard let self = self, self.supportsHaptics else { return }
                                                                    
            self.restartHapticEngine()
        }
    }
    
    package func triggerHapticShake() {
        guard let engine = engine else {
            print("[Haptic Engine]: Engine is nil.")
            return
        }

        do {
            // haptic pattern with a repeated "shake" effect
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            
            let event1 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let event2 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.1)
            let event3 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.2)
            
            let pattern = try CHHapticPattern(events: [event1, event2, event3], parameters: [])
            
            player = try engine.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch let error as NSError {
            print("Haptic shake failed: \(error.localizedDescription), Info: \(error.userInfo)")
        }
    }
    
    package func play(time: TimeInterval, intensity: Float, sharpness: Float) {
        guard let engine = engine else {
            print("[Haptic Engine]: Engine is nil.")
            return
        }

        // Abort if the device doesn't support haptics.
        guard supportsHaptics else {
            print("[Haptic Engine]: Device does not support haptics.")
            return
        }

        // The engine can be stopped even though it still exists. The common
        // cause here is the video recorder: attaching the microphone input
        // reconfigures the app's audio session, and CHHapticEngine stops itself
        // with `.audioSessionInterrupt` when that happens. `stoppedHandler` and
        // `resetHandler` record that in `engineNeedsStart`, but nothing acted on
        // it — `restartHapticEngine()` was only wired to
        // `willEnterForegroundNotification`. The result was that every haptic on
        // the video screen silently did nothing until the app was backgrounded
        // and foregrounded again. Start it here instead, so recovery doesn't
        // depend on the user leaving the app.
        if engineNeedsStart {
            do {
                try engine.start()
                engineNeedsStart = false
            } catch {
                print("[Haptic Engine]: Restart before playback failed: \(error)")
                return
            }
        }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)

            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A stop can land between the check above and playback, so treat a
            // failure as "needs starting" and retry once rather than dropping
            // the haptic.
            print("[Haptic Engine]: Playback failed, retrying once: \(error)")
            engineNeedsStart = true
            do {
                try engine.start()
                engineNeedsStart = false
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            } catch {
                print("[Haptic Engine]: Retry failed: \(error)")
            }
        }
    }
}

package extension HapticsManager {
    /// Light tick for button and icon presses.
    func tap() {
        guard supportsHaptics else { return }
        onMain {
            self.impactLight.impactOccurred(intensity: 0.9)
            self.impactLight.prepare()
        }
    }

    /// Subtle tick for selection changes: tabs, pickers, category pills.
    func selection() {
        guard supportsHaptics else { return }
        onMain {
            self.selectionGenerator.selectionChanged()
            self.selectionGenerator.prepare()
        }
    }

    /// Firm thud for significant actions: starting/stopping a recording.
    func impact() {
        guard supportsHaptics else { return }
        onMain {
            self.impactHeavy.impactOccurred()
            self.impactHeavy.prepare()
        }
    }

    /// Success notification for a completed capture.
    func success() {
        guard supportsHaptics else { return }
        onMain {
            self.notificationGenerator.notificationOccurred(.success)
            self.notificationGenerator.prepare()
        }
    }
}

/// Plain-looking button style that ticks on press-down and adds a subtle
/// press scale, so every tappable control shares the same feel.
package struct HapticButtonStyle: ButtonStyle {
    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { HapticsManager.shared.tap() }
            }
    }
}

package extension ButtonStyle where Self == HapticButtonStyle {
    static var haptic: HapticButtonStyle { HapticButtonStyle() }
}

/// A press style that scales the label down while held and springs it back to
/// identity on release. Scale-only (no haptic) so it never doubles up with the
/// taps the button actions already fire. Also renders the label plainly, so it
/// stands in for `.plain` while adding the press animation.
package struct PressableButtonStyle: ButtonStyle {
    /// Scale applied while the button is held, e.g. 0.9 for the shutter and
    /// 0.95 for icon and text buttons.
    let pressedScale: CGFloat

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55),
                       value: configuration.isPressed)
    }
}

package extension ButtonStyle where Self == PressableButtonStyle {
    /// Presses down to `scale`, springs back to identity on release.
    static func pressable(scale: CGFloat) -> PressableButtonStyle {
        PressableButtonStyle(pressedScale: scale)
    }
}
