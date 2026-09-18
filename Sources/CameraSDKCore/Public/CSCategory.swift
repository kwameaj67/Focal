//
//  CSCategory.swift
//  CameraSDKCore
//
//  A consumer-defined tag attached to captured media.
//

import Foundation

/// A capture category shown in the horizontal selector at the bottom of the
/// camera / video screens (e.g. "Profile", "Sticker", "Walk Around" for photos,
/// or "Driving", "Functional", "Engine" for videos).
///
/// The SDK is deliberately domain-agnostic: it knows nothing about what a
/// category *means*. The host app defines whatever categories it needs and the
/// selected one is handed back on every `CSPhotoResult` / `CSVideoResult`, so
/// the host can route or label the media however it likes.
public struct CSCategory: Identifiable, Hashable, Sendable {

    /// A stable identifier used for equality and for `startingCategoryID`
    /// look-ups. Not shown to the user.
    public let id: String

    /// The human-readable label rendered in the category selector.
    public let title: String

    /// Creates a category with an explicit identifier and display title.
    /// - Parameters:
    ///   - id: Stable identifier (e.g. `"AMKT"`).
    ///   - title: User-facing label (e.g. `"Profile"`).
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    /// Convenience initializer where the title doubles as the identifier.
    public init(_ title: String) {
        self.id = title
        self.title = title
    }
}
