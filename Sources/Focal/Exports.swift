//
//  Exports.swift
//  Focal
//
//  The umbrella module. It has no code of its own — it re-exports the three
//  real targets so that `import Focal` keeps giving you the whole
//  SDK, exactly as it did before the package was split.
//
//  Pick your import based on what you actually need:
//
//    import Focal        // everything (photo + video)
//    import FocalPhoto   // stills only — no microphone code linked
//    import FocalVideo   // recording only
//
//  Importing only Photo matters for more than binary size: the video target is
//  the only one that touches `AVCaptureDevice.default(for: .audio)`, so a
//  stills-only host has no reason to declare `NSMicrophoneUsageDescription`.
//
//  `@_exported import` is underscored, but it is the only way Swift offers to
//  build an umbrella module. It's confined to this one file so that if the
//  attribute ever changes, there is exactly one place to fix.
//

@_exported import FocalCore
@_exported import FocalPhoto
@_exported import FocalVideo
