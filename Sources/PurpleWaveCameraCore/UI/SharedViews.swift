//
//  SharedViews.swift
//  PurpleWaveCameraCore
//
//  Small reusable SwiftUI pieces used by both capture screens.
//

import SwiftUI

/// The rounded "1.0x" zoom indicator.
package struct ZoomBadge: View {
    package let text: String
    package var rotation: Double = 0

    package init(text: String, rotation: Double = 0) {
        self.text = text
        self.rotation = rotation
    }

    package var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(Circle().fill(Color.black.opacity(0.3)))
            .rotationEffect(.radians(rotation))
    }
}

/// The top-right item/sticker badge (e.g. "MO6759").
package struct IcnBadge: View {
    package let icn: String
    package var rotation: Double = 0

    package init(icn: String, rotation: Double = 0) {
        self.icn = icn
        self.rotation = rotation
    }

    package var body: some View {
        Text(icn)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.4)))
//            .rotationEffect(.radians(rotation))
    }
}

/// A transient yellow focus square drawn where the user tapped.
package struct FocusSquare: View {
    package let point: CGPoint

    package init(point: CGPoint) {
        self.point = point
    }

    package var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1)
            .frame(width: 66, height: 66)
            .position(point)
            .transition(.opacity)
    }
}

/// Shown full-screen when a required permission was denied, offering a jump to
/// Settings and a way out.
package struct PermissionDeniedView: View {
    package let permission: PWPermission
    package let onDismiss: () -> Void

    package init(permission: PWPermission, onDismiss: @escaping () -> Void) {
        self.permission = permission
        self.onDismiss = onDismiss
    }

    package var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Cancel", action: onDismiss)
                    .foregroundColor(.white)
                Button("Open Settings") { MediaPermissions.openSettings() }
                    .fontWeight(.semibold)
                    .foregroundColor(.yellow)
            }
        }
        .padding(32)
    }

    private var icon: String {
        switch permission {
        case .camera:       return "camera.fill"
        case .microphone:   return "mic.fill"
        case .photoLibrary: return "photo.on.rectangle.angled"
        case .location:     return "location.fill"
        }
    }

    private var message: String {
        switch permission {
        case .camera:
            return "Camera access is required to capture media. Enable it in Settings."
        case .microphone:
            return "Microphone access is required to record video. Enable it in Settings."
        case .photoLibrary:
            return "Photo library access is required. Enable it in Settings."
        case .location:
            return "Location access is required to tag captures. Enable it in Settings."
        }
    }
}

/// A thumbnail of the most recently captured media, tappable to review.
package struct RecentThumbnail: View {
    package let image: UIImage?
    package var rotation: Double = 0
    package var onTap: () -> Void = {}

    package init(
        image: UIImage?,
        rotation: Double = 0,
        onTap: @escaping () -> Void = {}
    ) {
        self.image = image
        self.rotation = rotation
        self.onTap = onTap
    }

    package var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .rotationEffect(.radians(rotation))
        .onTapGesture(perform: onTap)
        .allowsHitTesting(image != nil)
    }
}

// MARK: - Previews

#Preview("Badges and focus square") {
    ZStack {
        Color.black
        VStack(spacing: 28) {
            ZoomBadge(text: "1.0x")
            ZoomBadge(text: "4.8x")
            IcnBadge(icn: "MO6759")
            // Long labels are the failure case worth seeing: the badge has no
            // truncation, so an over-long sticker ID pushes the layout.
            IcnBadge(icn: "MO6759-REAR-AXLE")
        }
    }
    .ignoresSafeArea()
}

#Preview("Rotated for landscape") {
    // ZoomBadge counter-rotates; IcnBadge currently does not — its
    // `.rotationEffect` is commented out in the view, so it stays upright here
    // even though a rotation is passed. Kept side by side so the mismatch is
    // visible rather than a surprise on device.
    ZStack {
        Color.black
        HStack(spacing: 24) {
            ZoomBadge(text: "2.4x", rotation: .pi / 2)
            IcnBadge(icn: "MO6759", rotation: .pi / 2)
        }
    }
    .ignoresSafeArea()
}

#Preview("Focus square") {
    ZStack {
        Color.black
        FocusSquare(point: CGPoint(x: 190, y: 380))
    }
    .ignoresSafeArea()
}

#Preview("Permission denied — camera") {
    PermissionDeniedView(permission: .camera, onDismiss: {})
}

#Preview("Permission denied — location") {
    // The newest case; worth previewing to confirm the copy fits alongside the
    // older three without wrapping awkwardly.
    PermissionDeniedView(permission: .location, onDismiss: {})
}

#Preview("Captured pile") {
    ZStack {
        Color.black
        HStack(spacing: 30) {
            CapturedStackThumbnail(images: [])
            CapturedStackThumbnail(images: [
                UIImage(systemName: "photo")!,
                UIImage(systemName: "photo.fill")!,
                UIImage(systemName: "camera")!
            ])
        }
    }
    .ignoresSafeArea()
}
