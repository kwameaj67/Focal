//
//  CapturedGalleryPreview.swift
//  FocalPhoto
//
//  The photo screen's captured-media UI. The bottom-corner pile itself is
//  shared with the video screen and lives in Core as `CapturedStackThumbnail`.
//
//   • `CapturedPhotoItem` — one captured photo's encoded bytes plus a
//     thumbnail. Full-resolution images are decoded on demand, never held.
//   • `CapturedGalleryPreview` — the full-screen viewer opened on tap, with a
//     swipeable pager (category name at the bottom) and a grid toggle.
//
//  Presented by a `Transmission.PresentationLink` zoom transition from the pile.
//

import SwiftUI
import Transmission
import FocalCore

/// One captured (or imported) photo shown in the pile / preview.
///
/// Holds the **encoded** bytes plus a small thumbnail, never the full decoded
/// image. A decoded 12MP frame is ~47 MB; the same photo encoded is 1–2 MB, and
/// its thumbnail ~0.16 MB. Retaining decoded images meant a 30-shot session cost
/// roughly 1.4 GB and the app was jetsammed — measured, not estimated.
///
/// The host already received the full-resolution image and data through
/// `onCapture`, so this type exists purely to feed the pile and the preview.
/// Neither needs a full-size bitmap resident: the pile draws at 46pt, and the
/// pager decodes only the page being looked at.
struct CapturedPhotoItem: Identifiable {
    let id = UUID()

    /// Encoded HEIC/JPEG, exactly as delivered to the host.
    let data: Data

    /// Small bitmap for the pile and the grid. Always resident — it is cheap.
    let thumbnail: UIImage

    let category: FCCategory?

    /// Builds an item from the encoded bytes plus the full-size image the
    /// thumbnail is derived from.
    ///
    /// `image` is read and dropped — it is never stored. If downscaling fails
    /// the full image is kept as the thumbnail, which costs memory but is
    /// better than a pile of blank tiles; in practice this does not happen.
    init(data: Data, image: UIImage, category: FCCategory?) {
        self.data = data
        self.thumbnail = image.preparingThumbnail(of: Self.thumbnailSize) ?? image
        self.category = category
    }

    /// Big enough for the 120pt grid cell on a 3× screen, small enough that a
    /// hundred of them are still under 20 MB.
    private static let thumbnailSize = CGSize(width: 400, height: 400)
}

// MARK: - Full-screen gallery preview

struct CapturedGalleryPreview: View {

    let items: [CapturedPhotoItem]

    @State private var index: Int
    @State private var isGrid = false

    @Environment(\.presentationCoordinator) private var presentationCoordinator

    init(items: [CapturedPhotoItem], startIndex: Int) {
        self.items = items
        _index = State(initialValue: max(0, min(startIndex, items.count - 1)))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isGrid {
                gridView
            } else {
                pagerView
            }

            topBar
        }
        .statusBarHidden(true)
    }

    // MARK: Swipeable pager

    private var pagerView: some View {
        TabView(selection: $index) {
            ForEach(items.indices, id: \.self) { i in
                // Full-resolution decode for the current page and its immediate
                // neighbours only, so a swipe has the next image ready without
                // every photo in the session being resident at once.
                LazyDecodedPage(
                    item: items[i],
                    isActive: abs(i - index) <= 1
                )
                .overlay(alignment: .bottom) { categoryLabel(items[i].category) }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    // MARK: Grid

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    // Thumbnails here, always. The grid draws at 120pt, so a
                    // full-resolution decode per cell was pure waste.
                    Image(uiImage: items[i].thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottomLeading) {
                            if let title = items[i].category?.title {
                                Text(title)
                                    .font(FocalFont.rounded(11))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.5)))
                                    .padding(6)
                            }
                        }
                        .onTapGesture {
                            HapticsManager.shared.selection()
                            index = i
                            withAnimation { isGrid = false }
                        }
                }
            }
            .padding(8)
            .padding(.top, 64)   // clear the top bar
        }
    }

    // MARK: Chrome

    @ViewBuilder
    private func categoryLabel(_ category: FCCategory?) -> some View {
        if let title = category?.title {
            Text(title)
                .font(FocalFont.rounded(15))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, 44)
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    HapticsManager.shared.tap()
                    presentationCoordinator.dismiss()
                } label: {
                    chrome("xmark")
                }
                Spacer()
                // Toggle between the swipe pager and the grid.
                Button {
                    HapticsManager.shared.selection()
                    withAnimation { isGrid.toggle() }
                } label: {
                    chrome(isGrid ? "rectangle.portrait" : "square.grid.2x2")
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func chrome(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .padding(12)
            .background(Circle().fill(Color.black.opacity(0.4)))
    }
}

// MARK: - Single zoomable page

/// One page of the pager: pinch and double-tap to zoom. Pan is intentionally
/// omitted so horizontal drags stay with the pager's paging gesture.
private struct ZoomablePage: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(lastScale * value, 1), 4)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { withAnimation { reset() } }
                    }
            )
            .onTapGesture(count: 2) {
                HapticsManager.shared.tap()
                withAnimation(.easeInOut(duration: 0.25)) {
                    if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                }
            }
    }

    private func reset() {
        scale = 1
        lastScale = 1
    }
}

// MARK: - Lazily decoded page

/// A pager page that decodes its full-resolution image only while it is the
/// current page or an immediate neighbour, and drops it again afterwards.
///
/// Showing the thumbnail while inactive means a swipe never lands on an empty
/// frame — the low-resolution version is already there and is replaced as soon
/// as the decode finishes.
private struct LazyDecodedPage: View {

    let item: CapturedPhotoItem
    let isActive: Bool

    @State private var decoded: UIImage?

    var body: some View {
        Group {
            if let decoded {
                ZoomablePage(image: decoded)
            } else {
                // Placeholder at thumbnail resolution: visibly soft for a
                // moment, which is better than a black frame.
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFit()
            }
        }
        .task(id: isActive) {
            guard isActive else {
                // Released as the page moves away, which is the whole point.
                decoded = nil
                return
            }
            guard decoded == nil else { return }

            // Decode off the main actor; UIImage(data:) is lazy, so force the
            // bitmap here rather than on the first draw.
            let data = item.data
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingForDisplay()
            }.value

            if !Task.isCancelled { decoded = image }
        }
    }
}
