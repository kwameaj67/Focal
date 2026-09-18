//
//  DropAnimation.swift
//  CameraSDKCore
//
//  Shared "captured media tosses into the thumbnail" animation, used by both the
//  photo and video screens. The motion is a single smooth arc (U-shaped / arch)
//  from the shutter / record button up and over to the thumbnail, with a subtle
//  settle bounce as it lands.
//

import SwiftUI

// MARK: - Path math

/// Computes the flight path as a function of a single 0→1 progress value.
package enum CSDropPath {

    /// Total animation duration (seconds) — quick and snappy.
    package static let duration: TimeInterval = 0.5

    /// How high the arc bows above the higher of the two endpoints.
    private static let arcHeight: CGFloat = 120

    /// When (in normalized progress) the landing bounce starts.
    private static let bounceStart: CGFloat = 0.7

    /// Vertical size of the settle bounce (points).
    private static let bounceAmplitude: CGFloat = 14

    /// The flying image's un-scaled size; it shrinks to `landedSize`.
    package static let baseSize: CGFloat = 110
    private static let landedSize: CGFloat = 44

    /// Position along the arc for `progress ∈ [0, 1]`.
    package static func point(progress: CGFloat, start: CGPoint, end: CGPoint) -> CGPoint {
        // Ease-in-out for a smooth launch and landing along one continuous arc.
        let t = easeInOut(progress)

        // Both control points sit above the endpoints, bowing the curve into a
        // smooth arch (no corner) between the start and the thumbnail.
        let peakY = Swift.min(start.y, end.y) - arcHeight
        let c1 = CGPoint(x: start.x, y: peakY)
        let c2 = CGPoint(x: end.x, y: peakY)
        var p = cubicBezier(start, c1, c2, end, t)

        // A small damped nudge near the end so it "settles" into the slot.
        if progress > bounceStart {
            let u = Double((progress - bounceStart) / (1 - bounceStart)) // 0→1
            let bounce = -Double(bounceAmplitude) * (1 - u) * sin(2 * Double.pi * u)
            p.y += CGFloat(bounce)
        }
        return p
    }

    /// Scale factor of the flying image: shrinks smoothly from 1 → landed/base.
    package static func scale(progress: CGFloat) -> CGFloat {
        let ratio = landedSize / baseSize
        return 1 - (1 - ratio) * easeInOut(progress)
    }

    private static func easeInOut(_ x: CGFloat) -> CGFloat {
        let x = Double(x)
        let v = x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
        return CGFloat(v)
    }

    private static func cubicBezier(
        _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat
    ) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }
}

// MARK: - Geometry effect

/// Places (and shrinks) the flying capture image along `CSDropPath`.
///
/// The key detail: `animatableData` **is** the progress, so SwiftUI evaluates
/// `effectValue` at every interpolated frame of the animation — which is what
/// makes the view actually travel the curve instead of cutting straight across
/// (a plain `.position` bound to a computed point only lerps start→end).
package struct CSDropEffect: GeometryEffect {
    package var progress: CGFloat
    package var start: CGPoint
    package var end: CGPoint

    package init(progress: CGFloat, start: CGPoint, end: CGPoint) {
        self.progress = progress
        self.start = start
        self.end = end
    }

    package var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    package func effectValue(size: CGSize) -> ProjectionTransform {
        let point = CSDropPath.point(progress: progress, start: start, end: end)
        let scale = CSDropPath.scale(progress: progress)

        // Compose: move the view's centre to the origin, scale about it, then
        // translate that centre onto the arc point (all in the parent's space).
        let toCenter = CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
        let scaling = CGAffineTransform(scaleX: scale, y: scale)
        let toPoint = CGAffineTransform(translationX: point.x, y: point.y)
        return ProjectionTransform(toCenter.concatenating(scaling).concatenating(toPoint))
    }
}

// MARK: - Thumbnail anchor

/// Reports the thumbnail's frame (as an `Anchor<CGRect>`) up the view tree so
/// the drop animation knows where to land.
package struct ThumbnailAnchorKey: PreferenceKey {
    package static var defaultValue: Anchor<CGRect>? = nil
    package static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

package extension View {
    /// Publishes this view's bounds as the drop-animation landing target.
    func thumbnailAnchor() -> some View {
        anchorPreference(key: ThumbnailAnchorKey.self, value: .bounds) { $0 }
    }
}

// MARK: - Flight overlay

/// The flying media image that arcs into the thumbnail. Attach it via
/// `.overlayPreferenceValue(ThumbnailAnchorKey.self)` so it reads the live
/// thumbnail position. Renders nothing when `image` is `nil`.
package struct DropFlightOverlay: View {
    package let image: UIImage?
    package let progress: CGFloat
    package let anchor: Anchor<CGRect>?

    package init(image: UIImage?, progress: CGFloat, anchor: Anchor<CGRect>?) {
        self.image = image
        self.progress = progress
        self.anchor = anchor
    }

    package var body: some View {
        GeometryReader { proxy in
            if let image, let anchor {
                let endRect = proxy[anchor]
                let start = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 150)
                let end = CGPoint(x: endRect.midX, y: endRect.midY)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: CSDropPath.baseSize, height: CSDropPath.baseSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .modifier(CSDropEffect(progress: progress, start: start, end: end))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
