// swift-tools-version:5.9
//
//  Package.swift
//  PurpleWaveCamera
//
//  A SwiftUI-first camera package: a photo capture screen and a landscape video
//  recorder, with AVFoundation doing the heavy lifting.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Which product to depend on
//  ─────────────────────────────────────────────────────────────────────────
//  • PurpleWaveCamera       — everything. `import PurpleWaveCamera` behaves
//                             exactly as it did before the package was split.
//  • PurpleWaveCameraPhoto  — stills only. Links no microphone code, so the
//                             host needs no NSMicrophoneUsageDescription and
//                             discloses no microphone access.
//  • PurpleWaveCameraVideo  — recording only.
//
//  Core is a dependency of both capture targets and is listed as a product so a
//  host can build directly against the session plumbing (a barcode scanner, for
//  instance) without pulling in either screen.
//
//  Cross-target internals use Swift 5.9's `package` access level, so splitting
//  the module did not widen the public API.
//
//  Apple frameworks (AVFoundation, SwiftUI, Photos, CoreMotion, UIKit) plus one
//  third-party dependency, Transmission, for the zoom transition used by the
//  full-screen photo preview.
//

import PackageDescription

let package = Package(
    name: "PurpleWaveCamera",
    // iOS 17 minimum: lets us use modern AVFoundation (maxPhotoDimensions),
    // SwiftUI navigation, and custom sheet detents without availability shims.
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "PurpleWaveCamera",      targets: ["PurpleWaveCamera"]),
        .library(name: "PurpleWaveCameraPhoto", targets: ["PurpleWaveCameraPhoto"]),
        .library(name: "PurpleWaveCameraVideo", targets: ["PurpleWaveCameraVideo"]),
        .library(name: "PurpleWaveCameraCore",  targets: ["PurpleWaveCameraCore"])
    ],
    dependencies: [
        // `.upToNextMinor` rather than `from:` on purpose. `from: "2.14.4"`
        // permits any 2.x, so the package and the demo project resolved
        // independently and landed on different versions (2.14.4 vs 2.16.0).
        // Xcode then cannot build a single graph across the local package
        // reference and reports "Missing package product 'PurpleWaveCamera'",
        // which points nowhere near the actual cause. Constraining to 2.14.x
        // forces every resolution context to agree.
        .package(url: "https://github.com/nathantannar4/Transmission", .upToNextMinor(from: "2.14.4")),
    ],
    targets: [
        // Session lifecycle, device selection and controls, orientation,
        // camera + photo-library permissions, the gallery picker, and the
        // views both screens share. Knows nothing about the microphone.
        .target(
            name: "PurpleWaveCameraCore",
            path: "Sources/PurpleWaveCameraCore"
        ),

        // Stills: photo output, per-shot settings, flash, the capture screen.
        .target(
            name: "PurpleWaveCameraPhoto",
            dependencies: [
                "PurpleWaveCameraCore",
                .product(name: "Transmission", package: "Transmission")
            ],
            path: "Sources/PurpleWaveCameraPhoto"
        ),

        // Recording: movie output, the microphone input and its permission,
        // per-category presets, torch, the recorder screen.
        .target(
            name: "PurpleWaveCameraVideo",
            dependencies: [
                "PurpleWaveCameraCore",
                .product(name: "Transmission", package: "Transmission")
            ],
            path: "Sources/PurpleWaveCameraVideo"
        ),

        // Umbrella. Source-free apart from the re-exports in Exports.swift.
        .target(
            name: "PurpleWaveCamera",
            dependencies: ["PurpleWaveCameraCore", "PurpleWaveCameraPhoto", "PurpleWaveCameraVideo"],
            path: "Sources/PurpleWaveCamera"
        ),

        // Unit tests for the pure, hardware-independent logic (config
        // resolution, enum bridging, orientation math, output directory).
        // Depends on the three real targets rather than the umbrella, because
        // `@testable` reaches into one module at a time — importing the
        // umbrella would only expose the umbrella's own (empty) internals.
        .testTarget(
            name: "PurpleWaveCameraTests",
            dependencies: [
                "PurpleWaveCameraCore",
                "PurpleWaveCameraPhoto",
                "PurpleWaveCameraVideo"
            ],
            path: "Tests/PurpleWaveCameraTests"
        )
    ]
)
