// swift-tools-version:5.9
//
//  Package.swift
//  CameraSDK
//
//  A SwiftUI-first camera package: a photo capture screen and a landscape video
//  recorder, with AVFoundation doing the heavy lifting.
//
//  ─────────────────────────────────────────────────────────────────────────
//  Which product to depend on
//  ─────────────────────────────────────────────────────────────────────────
//  • CameraSDK       — everything. `import CameraSDK` behaves
//                             exactly as it did before the package was split.
//  • CameraSDKPhoto  — stills only. Links no microphone code, so the
//                             host needs no NSMicrophoneUsageDescription and
//                             discloses no microphone access.
//  • CameraSDKVideo  — recording only.
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
    name: "camera-sdk-ios",
    // iOS 17 minimum: lets us use modern AVFoundation (maxPhotoDimensions),
    // SwiftUI navigation, and custom sheet detents without availability shims.
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "CameraSDK",      targets: ["CameraSDK"]),
        .library(name: "CameraSDKPhoto", targets: ["CameraSDKPhoto"]),
        .library(name: "CameraSDKVideo", targets: ["CameraSDKVideo"]),
        .library(name: "CameraSDKCore",  targets: ["CameraSDKCore"])
    ],
    dependencies: [
        // `.upToNextMinor` rather than `from:` on purpose. `from: "2.14.4"`
        // permits any 2.x, so the package and the demo project resolved
        // independently and landed on different versions (2.14.4 vs 2.16.0).
        // Xcode then cannot build a single graph across the local package
        // reference and reports "Missing package product 'CameraSDK'",
        // which points nowhere near the actual cause. Constraining to 2.14.x
        // forces every resolution context to agree.
        .package(url: "https://github.com/nathantannar4/Transmission", .upToNextMinor(from: "2.16.0")),
    ],
    targets: [
        // Session lifecycle, device selection and controls, orientation,
        // camera + photo-library permissions, the gallery picker, and the
        // views both screens share. Knows nothing about the microphone.
        .target(
            name: "CameraSDKCore",
            path: "Sources/CameraSDKCore",
            resources: [
                // Bundled font, registered at runtime via `Bundle.module`
                // (package resources are not picked up by Info.plist UIAppFonts).
                .process("Resources/Fonts/CashMarket-BoldRounded.ttf")
            ]
        ),

        // Stills: photo output, per-shot settings, flash, the capture screen.
        .target(
            name: "CameraSDKPhoto",
            dependencies: [
                "CameraSDKCore",
                .product(name: "Transmission", package: "Transmission")
            ],
            path: "Sources/CameraSDKPhoto"
        ),

        // Recording: movie output, the microphone input and its permission,
        // per-category presets, torch, the recorder screen.
        .target(
            name: "CameraSDKVideo",
            dependencies: [
                "CameraSDKCore",
                .product(name: "Transmission", package: "Transmission")
            ],
            path: "Sources/CameraSDKVideo"
        ),

        // Umbrella. Source-free apart from the re-exports in Exports.swift.
        .target(
            name: "CameraSDK",
            dependencies: ["CameraSDKCore", "CameraSDKPhoto", "CameraSDKVideo"],
            path: "Sources/CameraSDK"
        ),

        // Unit tests for the pure, hardware-independent logic (config
        // resolution, enum bridging, orientation math, output directory).
        // Depends on the three real targets rather than the umbrella, because
        // `@testable` reaches into one module at a time — importing the
        // umbrella would only expose the umbrella's own (empty) internals.
        .testTarget(
            name: "CameraSDKTests",
            dependencies: [
                "CameraSDKCore",
                "CameraSDKPhoto",
                "CameraSDKVideo"
            ],
            path: "Tests/CameraSDKTests"
        )
    ]
)
