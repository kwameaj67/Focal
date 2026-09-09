# PurpleWaveCamera

A Swift Package that renders a **camera capture screen** and a **landscape video
recorder** for iOS. Built SwiftUI-first, with AVFoundation doing the capture
work. Extracted and generalized from FieldTool's enhanced camera and video
recorder so it can be dropped into any app with no FieldTool dependencies.

- **iOS 16+**, Swift 5.9.
- **Callback / delegate based** — the SDK captures media and hands it back; your
  app decides how to store or upload it.
- **One dependency**: [Transmission](https://github.com/nathantannar4/Transmission)
  (`2.14.4+`), used for the zoom transition on the full-screen photo preview.
  SwiftPM resolves it automatically.

---

## Features

Both screens share the same capture feature set:

| Feature | Photo | Video |
| --- | :---: | :---: |
| Live preview | ✅ | ✅ |
| Pinch to zoom (1×–5×) | ✅ | ✅ |
| Tap to focus / expose | ✅ | ✅ |
| Flash (photo) / Torch (video) | ✅ | ✅ |
| Ultra-wide ↔ wide lens switch | ✅ | ✅ |
| Custom multi-select gallery import | ✅ | ✅ |
| Consumer-defined category selector | ✅ (scroll) | ✅ (segmented) |
| Optional save-to-photo-library | ✅ | ✅ |
| Multi-capture (screen stays open) | ✅ | ✅ |
| Capture "drop into thumbnail" animation | ✅ | ✅ |
| Tap thumbnail → full-screen preview (zoom) | ✅ image | ✅ plays video |
| Landscape-locked recording | — | ✅ |
| Recording timer w/ optional auto-stop | — | ✅ |

> The video screen is **landscape-only while recording**: in portrait it shows a
> "rotate to landscape" overlay and disables the record button.

---

## Installation

### Swift Package Manager

In Xcode: **File ▸ Add Package Dependencies…** and point at this repository, or
add it to a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<your-org>/purplewave-camera-ios.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "PurpleWaveCamera", package: "purplewave-camera-ios")
    ])
]
```

For local development you can also drag the `purplewave-camera-ios` folder in as a local
package.

---

## Required Info.plist keys

A Swift package **cannot** declare privacy usage strings on your behalf — you
must add these to the **host app's** `Info.plist` or the app will crash when the
SDK requests access:

| Key | Needed for |
| --- | --- |
| `NSCameraUsageDescription` | Always (camera preview + capture) |
| `NSMicrophoneUsageDescription` | Video recording (audio) |
| `NSPhotoLibraryUsageDescription` | Gallery import |
| `NSPhotoLibraryAddUsageDescription` | `savesToPhotoLibrary = true` |

Example:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture photos and videos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used to record audio with your videos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to import photos and videos from your library.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Used to save captured media to your photo library.</string>
```

The SDK requests the permissions it needs on launch and shows a
"Open Settings" screen if one was denied.

---

## Quick start

### SwiftUI

```swift
import SwiftUI
import PurpleWaveCamera

struct CaptureExample: View {
    @State private var showCamera = false

    var body: some View {
        Button("Take photos") { showCamera = true }
            .fullScreenCover(isPresented: $showCamera) {
                PWCameraScreen(
                    config: PWCameraConfig(
                        categories: [
                            PWCategory(id: "AMKT", title: "Profile"),
                            PWCategory(id: "STICKER", title: "Sticker"),
                            PWCategory(id: "WALK", title: "Walk Around")
                        ],
                        startingCategoryID: "AMKT",
                        overlayLabel: "MO6759"
                    ),
                    handlers: PWPhotoHandlers(
                        onCapture: { result in
                            // result.imageData, result.image, result.category …
                            print("Captured a \(result.category?.title ?? "photo")")
                        },
                        onFinish: { _ in showCamera = false }
                    )
                )
            }
    }
}
```

### UIKit

```swift
import UIKit
import PurpleWaveCamera

final class MyViewController: UIViewController {
    func openCamera() {
        let vc = PWCamera.makePhotoCapture(
            config: PWCameraConfig(categories: [PWCategory("Profile")]),
            handlers: PWPhotoHandlers(
                onCapture: { result in /* store result */ },
                onFinish:  { _ in /* controller dismisses itself */ }
            )
        )
        present(vc, animated: true)
    }
}
```

A delegate-based overload is also available:

```swift
let vc = PWCamera.makePhotoCapture(config: config, delegate: self)
// self: PWPhotoCaptureDelegate  (held weakly)
```

### Video

```swift
PWVideoScreen(
    config: PWVideoConfig(
        categories: [
            PWCategory("Driving"),
            PWCategory("Functional"),
            PWCategory("Engine")
        ],
        maxDuration: 180,                       // auto-stop after 3 minutes
        presetByCategoryID: ["Driving": .hd1080],
        defaultPreset: .hd720
    ),
    handlers: PWVideoHandlers(
        onRecord: { result in
            // result.fileURL is a local .mov you now own — move or upload it
        },
        onFinish: { _ in /* dismiss */ }
    )
)
```

UIKit: `PWCamera.makeVideoRecorder(config:handlers:)` /
`makeVideoRecorder(config:delegate:)`.

---

## Configuration reference

### `PWCameraConfig` (photo)

| Property | Default | Description |
| --- | --- | --- |
| `categories` | `[]` | Pills in the category scroll bar. Empty hides it. |
| `startingCategoryID` | `nil` | Selected category on launch (falls back to first). |
| `defaultFlashMode` | `.auto` | `.auto` / `.on` / `.off`. |
| `allowsGallery` | `true` | Show the library-import button. |
| `allowsUltraWide` | `true` | Show the ultra-wide toggle (device permitting). |
| `savesToPhotoLibrary` | `false` | Also save captures to the `FTCamera` album (name kept for continuity). |
| `overlayLabel` | `nil` | Top-right badge text (e.g. an item ID). |
| `outputDirectory` | `nil` | Where file helpers write; temp dir if `nil`. |

### `PWVideoConfig` (video)

| Property | Default | Description |
| --- | --- | --- |
| `categories` | `[]` | Segments in the category control. |
| `startingCategoryID` | `nil` | Selected category on launch. |
| `maxDuration` | `nil` | Auto-stop length in seconds; `nil` = unlimited. |
| `presetByCategoryID` | `[:]` | Per-category capture quality. |
| `defaultPreset` | `.hd1080` | Quality for unlisted categories. |
| `allowsTorch` | `true` | Show the torch button. |
| `allowsUltraWide` | `true` | Show the ultra-wide toggle. |
| `allowsGallery` | `true` | Show the library-import button. |
| `savesToPhotoLibrary` | `false` | Also save recordings to the `FTCamera` album (name kept for continuity). |
| `maxFileSizeMB` | `400` | Reject imported videos larger than this. |
| `overlayLabel` | `nil` | Top-right badge text. |
| `outputDirectory` | `nil` | Where recordings are written; temp dir if `nil`. |

---

## Results

`onCapture` / `onRecord` fire **once per item** (the screen stays open for
multi-capture). `onFinish` fires when the user leaves via Done or Cancel.

### `PWPhotoResult`
- `imageData: Data` — encoded (HEVC/JPEG) bytes.
- `image: UIImage` — decoded image.
- `category: PWCategory?` — selected category (if any).
- `source: .camera | .gallery`
- `orientation: UIDeviceOrientation` — device orientation at capture.
- `metadata: [String: Any]?` — capture metadata when available.

### `PWVideoResult`
- `fileURL: URL` — local `.mov` file; **ownership transfers to you** (move or
  delete it — the SDK writes to a temp directory by default).
- `category: PWCategory?`
- `duration: TimeInterval`
- `thumbnail: UIImage?`
- `source: .camera | .gallery`

---

## Permissions API

If you'd rather gate access yourself before presenting a screen:

```swift
let denied = await MediaPermissions.ensureVideoPermissions(needsLibrary: true)
if denied == nil {
    // present PWVideoScreen
} else {
    MediaPermissions.openSettings()
}
```

Also available: `cameraStatus()`, `requestCamera()`, `requestMicrophone()`,
`photoLibraryStatus()`, `requestPhotoLibrary()`, `ensurePhotoPermissions()`.

---

## Architecture

Four targets. Three do the work; the fourth is an umbrella that re-exports them
so `import PurpleWaveCamera` gives you everything, as it always did.

```
PurpleWaveCameraCore ──┬── PurpleWaveCameraPhoto ──┐
                       │                           ├── PurpleWaveCamera
                       └── PurpleWaveCameraVideo ──┘        (umbrella)
```

```
Sources/
├─ PurpleWaveCameraCore/     everything both capture modes share
│  ├─ Engine/       CameraSessionController (session, device, queue, zoom,
│  │                focus, lens swap), the preview UIViewRepresentable,
│  │                orientation monitor, haptics, photo-library saving
│  ├─ Gallery/      SwiftUI multi-select PHAsset picker + import helpers
│  ├─ Permissions/  Camera / photo-library helpers (no microphone)
│  ├─ Public/       PWCategory, shared result values, the PWCamera namespace
│  └─ UI/           Category bar, drop animation, shared badges/overlays
├─ PurpleWaveCameraPhoto/    stills: photo output, flash, PWCameraScreen
├─ PurpleWaveCameraVideo/    recording: movie output, microphone, torch,
│                            presets, PWVideoScreen
└─ PurpleWaveCamera/         umbrella; re-exports the three above
```

### Which target to depend on

| Depend on | You get | Microphone |
| --- | --- | --- |
| `PurpleWaveCamera` | Everything (photo + video) | Required |
| `PurpleWaveCameraPhoto` | Stills only | **Not needed** |
| `PurpleWaveCameraVideo` | Recording only | Required |
| `PurpleWaveCameraCore` | Session plumbing, no screens | Not needed |

The microphone column is the reason the package is split. Every
`AVCaptureDevice` audio call — querying authorization, requesting it, and
attaching the input — lives in `PurpleWaveCameraVideo`. A host that depends only
on `PurpleWaveCameraPhoto` links none of it, so it needs no
`NSMicrophoneUsageDescription` and discloses no microphone access in App Store
privacy details. (Requesting microphone access without that Info.plist key
crashes the app, so this is a correctness boundary, not just tidiness.)

Splitting did not widen the public API. Types that cross a target boundary but
aren't meant for hosts — `CameraSessionController`, the shared views, the
gallery — use Swift 5.9's `package` access level, so they're visible inside the
package and invisible outside it. The public surface is the same 20 types it was
before the split.

Design notes:

- **Engines are plain `ObservableObject`s**, not view controllers, so SwiftUI
  owns them as `@StateObject`. All `AVCaptureSession` mutation happens on a
  dedicated serial queue; all published state updates on the main actor.
- **Preview** uses a `UIView` whose backing layer *is* an
  `AVCaptureVideoPreviewLayer` (via `layerClass`), so it resizes for free.
- **Orientation** is read from the accelerometer (CoreMotion), not
  `UIDevice.orientation`, so overlays and capture orientation follow how the
  phone is physically held even if the app's UI is orientation-locked.
- **Categories are domain-agnostic**: the SDK never interprets a category, it
  just returns the selected one on every result.

### What was intentionally left out

This SDK is a clean rebuild of FieldTool's camera mechanics. It does **not**
include FieldTool business logic: Realm/CoreData persistence, the upload queue,
telemetry, CDN wiring, Intercom, or VIN/barcode scanning. Those remain the
host app's responsibility — feed the `PWPhotoResult` / `PWVideoResult` into your
own pipeline.

---

## License

Proprietary — © Purple Wave, Inc. Internal use.
