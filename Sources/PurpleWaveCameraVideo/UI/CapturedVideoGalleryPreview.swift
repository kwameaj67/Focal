//
//  CapturedVideoGalleryPreview.swift
//  PurpleWaveCameraVideo
//
//  The video screen's captured-media preview: a swipeable pager that plays each
//  recorded clip (category name at the bottom) plus a grid toggle. Presented by
//  a `Transmission.PresentationLink` zoom transition from the thumbnail pile.
//  Reuses `CapturedStackThumbnail` for the bottom-corner pile.
//

import AVFoundation
import AVKit
import SwiftUI
import Transmission
import PurpleWaveCameraCore

/// One recorded (or imported) video shown in the pile / preview.
struct CapturedVideoItem: Identifiable {
    let id = UUID()
    let thumbnail: UIImage?
    let url: URL
    let category: PWCategory?

    /// Whether this clip was recorded here or imported from the library. The
    /// grid uses it to decide its column count — see `CapturedVideoGalleryPreview`.
    let source: PWCaptureSource

    /// Width ÷ height of the thumbnail, or `nil` when there's no thumbnail to
    /// measure. Read from the already-decoded image, so this costs nothing.
    var aspectRatio: CGFloat? {
        guard let thumbnail, thumbnail.size.height > 0 else { return nil }
        return thumbnail.size.width / thumbnail.size.height
    }

    /// `true` when the thumbnail is within a small tolerance of 16:9 in either
    /// orientation. Camera clips always are; library imports often aren't.
    var isWidescreen: Bool {
        guard let aspectRatio else { return true }   // unmeasurable: assume 16:9
        let sixteenByNine: CGFloat = 16.0 / 9.0
        let normalized = aspectRatio < 1 ? 1 / aspectRatio : aspectRatio
        return abs(normalized - sixteenByNine) < 0.15
    }
}

struct CapturedVideoGalleryPreview: View {

    let items: [CapturedVideoItem]

    @State private var index: Int
    @State private var isGrid = false

    @Environment(\.presentationCoordinator) private var presentationCoordinator

    init(items: [CapturedVideoItem], startIndex: Int) {
        self.items = items
        _index = State(initialValue: max(0, min(startIndex, items.count - 1)))
    }

    /// Three columns normally. Drops to two as soon as any imported clip isn't
    /// 16:9, because portrait and square library video is unreadable at
    /// one-third width. A `LazyVGrid` takes a single column count for the whole
    /// grid, so this is necessarily a property of the set rather than per row —
    /// one odd import widens every tile.
    private var columns: [GridItem] {
        let hasNonWidescreenImport = items.contains {
            $0.source == .gallery && !$0.isWidescreen
        }
        let count = hasNonWidescreenImport ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

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
                VideoPage(url: items[i].url, isActive: i == index)
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
            // Rows are as tall as their tallest tile and shorter tiles centre
            // within that, so a row mixing portrait and landscape clips will
            // show some vertical gap. That's the trade for not cropping.
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    GridVideoTile(url: items[i].url, thumbnail: items[i].thumbnail)
                        // Each tile takes its own shape rather than a fixed
                        // 120pt box. `.fit` means nothing is cropped, so a
                        // portrait or square import shows its whole frame —
                        // previously the fixed height cut the top and bottom
                        // off anything that wasn't roughly 16:9.
                        .aspectRatio(items[i].aspectRatio ?? 16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
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
            .padding(.top, 64)
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

// MARK: - Single video page

/// One page of the pager. Only the active page owns a live `AVPlayer` (created
/// when it becomes active, torn down when it leaves) so we never play several
/// clips at once or hold a player per video.
private struct VideoPage: View {
    let url: URL
    let isActive: Bool

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: isActive) { _ , active in
            if active { activate() } else { deactivate() }
        }
        .onAppear { if isActive { activate() } }
        .onDisappear { deactivate() }
    }

    private func activate() {
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
    }

    private func deactivate() {
        player?.pause()
        player = nil
    }
}

// MARK: - Auto-playing grid tile

/// A grid cell that silently auto-plays the first few seconds of its clip on a
/// loop (like the Photos grid). Falls back to the thumbnail until the first
/// frame renders, and only owns a player while it's on screen.
private struct GridVideoTile: View {
    let url: URL
    let thumbnail: UIImage?

    /// How far into each clip the loop preview plays before restarting.
    private let previewLimit = CMTime(seconds: 3, preferredTimescale: 600)

    @State private var player: AVPlayer?
    @State private var boundaryToken: Any?
    @State private var endToken: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }

            if let player {
                PlayerLayerView(player: player)
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        guard player == nil else { return }
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none
        player = newPlayer

        // Loop back to the start once the 3-second preview point is reached.
        boundaryToken = newPlayer.addBoundaryTimeObserver(
            forTimes: [NSValue(time: previewLimit)],
            queue: .main
        ) { [weak newPlayer] in
            newPlayer?.seek(to: .zero)
        }

        // Clips shorter than the preview limit loop at their natural end.
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        newPlayer.play()
    }

    private func stop() {
        if let boundaryToken { player?.removeTimeObserver(boundaryToken) }
        boundaryToken = nil
        if let endToken { NotificationCenter.default.removeObserver(endToken) }
        endToken = nil
        player?.pause()
        player = nil
    }
}

// MARK: - Chrome-free player layer

/// A minimal `AVPlayerLayer`-backed view (no transport controls), so grid tiles
/// render video like an image rather than a `VideoPlayer`.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
