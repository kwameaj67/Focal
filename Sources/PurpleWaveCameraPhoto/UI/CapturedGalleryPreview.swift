//
//  CapturedGalleryPreview.swift
//  PurpleWaveCameraPhoto
//
//  The photo screen's captured-media UI. The bottom-corner pile itself is
//  shared with the video screen and lives in Core as `CapturedStackThumbnail`.
//
//   • `CapturedPhotoItem` — one captured image plus its category.
//   • `CapturedGalleryPreview` — the full-screen viewer opened on tap, with a
//     swipeable pager (category name at the bottom) and a grid toggle.
//
//  Presented by a `Transmission.PresentationLink` zoom transition from the pile.
//

import SwiftUI
import Transmission
import PurpleWaveCameraCore

/// One captured (or imported) photo shown in the pile / preview.
struct CapturedPhotoItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let category: PWCategory?
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
                ZoomablePage(image: items[i].image)
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
                    Image(uiImage: items[i].image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottomLeading) {
                            if let title = items[i].category?.title {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
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
    private func categoryLabel(_ category: PWCategory?) -> some View {
        if let title = category?.title {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
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
