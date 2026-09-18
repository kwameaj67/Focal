//
//  CameraSessionController+Audio.swift
//  FocalVideo
//
//  Microphone attachment lives here rather than in Core on purpose. It is the
//  only code in the SDK that touches `AVCaptureDevice.default(for: .audio)`, so
//  keeping it in the video target means a host that links only
//  FocalPhoto never pulls in microphone code — and therefore has no
//  reason to declare `NSMicrophoneUsageDescription` or disclose microphone
//  access in App Store privacy details.
//
//  If this ever moves back into Core, that isolation is silently lost.
//

import AVFoundation
import FocalCore

extension CameraSessionController {

    /// Adds the default microphone as an audio input.
    ///
    /// Must be called on `sessionQueue`, inside a configuration transaction.
    ///
    /// - Throws: `FCCameraError.sessionConfigurationFailed` if there's no
    ///   microphone or the input can't be added.
    nonisolated func attachAudioInput() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            throw FCCameraError.sessionConfigurationFailed("No microphone available")
        }
        let input = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(input) else {
            throw FCCameraError.sessionConfigurationFailed("Cannot add audio input")
        }
        session.addInput(input)
    }
}
