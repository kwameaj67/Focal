//
//  MediaType.swift
//  CameraSDKCore
//
//  The kind of media a capture screen or gallery deals in. Vendored into this
//  package so it carries no external dependency; kept deliberately framework-free
//  (no Photos, no AVFoundation) so it can be shared by any layer. The Photos
//  bridging (`phMediaType`) and UI phrasing (`pluralNoun`) live alongside the
//  gallery model, which is the only place that needs them.
//

/// Whether a capture or picker is working with stills or moving images.
public enum MediaType: String, Sendable, CaseIterable {
    case image
    case video

    /// The singular, machine-ish name of the type ("image" / "video").
    public var prettyPrint: String { rawValue }
}
