//
//  CapturedStackThumbnail.swift
//  FocalCore
//
//  The bottom-corner "pile" of recent captures. It lives in Core because both
//  capture screens use it and it is genuinely mode-agnostic: it takes plain
//  `UIImage`s, so the photo screen feeds it captured stills and the video
//  screen feeds it recording thumbnails.
//

import SwiftUI

/// A small "pile" of the most recent captures, newest on top and older ones
/// peeking out behind, so the user can see up to three at once.
package struct CapturedStackThumbnail: View {
    package let images: [UIImage]

    private let size: CGFloat = 46

    package init(images: [UIImage]) {
        self.images = images
    }

    package var body: some View {
        // oldest → newest, capped at the last three
        let recent = Array(images.suffix(3))

        ZStack {
            if recent.isEmpty {
                Color.clear.frame(width: size, height: size)
            } else {
                ForEach(Array(recent.enumerated()), id: \.offset) { pair in
                    // depth 0 == front (newest); higher == further back
                    let depth = CGFloat(recent.count - 1 - pair.offset)
                    Image(uiImage: pair.element)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .scaleEffect(1 - depth * 0.08)
                        .offset(y: -depth * 6)
                        .zIndex(Double(pair.offset))
                }
            }
        }
        // Extra height leaves room for the upward peek of the back cards.
        .frame(width: size, height: size + 14)
    }
}
