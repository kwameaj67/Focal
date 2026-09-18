//
//  FocalFont.swift
//  FocalCore
//
//  The SDK's bundled display font (CashMarket Bold Rounded).
//
//  A font shipped as a Swift-package resource is not registered the way an app's
//  Info.plist `UIAppFonts` entries are, so it has to be registered at runtime
//  from `Bundle.module`. That happens once, lazily, the first time the font is
//  requested.
//

import CoreText
import SwiftUI

package enum FocalFont {

    /// PostScript name inside the .ttf — the name `Font.custom` resolves against.
    private static let name = "CashMarket-BoldRounded"

    /// Registers the bundled font exactly once. The lazy static makes this
    /// idempotent and thread-safe; the result records whether registration
    /// succeeded so callers can fall back gracefully.
    private static let isRegistered: Bool = {
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
            return false
        }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// The bundled font at `size`. Falls back to the system rounded-bold face if
    /// the resource is ever missing, so text never silently disappears.
    package static func rounded(_ size: CGFloat) -> Font {
        isRegistered
            ? .custom(name, size: size)
            : .system(size: size, weight: .bold, design: .rounded)
    }
}
