//
//  MediaGalleryScreen.swift
//  FocalCore
//


import Photos
import SwiftUI

package struct MediaGalleryScreen: View {

    @StateObject private var model: MediaGalleryModel

    /// Called with the final selection when the user taps Done.
    package let onDone: ([PHAsset]) -> Void
    /// Called when the user cancels.
    package let onCancel: () -> Void

    /// What the body should show. Kept as one value rather than a pair of
    /// booleans so "still fetching" and "nothing to show" can never both be
    /// true — the bug that made an empty grid look identical to a slow one.
    private enum LoadState {
        case loading
        case denied
        case loaded
    }

    @State private var state: LoadState = .loading

    /// Whether access is limited to a user-picked subset. An empty grid means
    /// something different then, and the user can do something about it.
    @State private var isLimited = false

    package init(
        mediaType: MediaType,
        onDone: @escaping ([PHAsset]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: MediaGalleryModel(mediaType: mediaType))
        self.onDone = onDone
        self.onCancel = onCancel
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    package var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    deniedState
                case .loaded where model.isEmpty:
                    emptyState
                case .loaded:
                    grid
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .font(FocalFont.rounded(17))
                        .buttonStyle(.pressable(scale: 0.95))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(model.selected) }
                        .font(FocalFont.rounded(17))
                        .buttonStyle(.pressable(scale: 0.95))
                        .disabled(model.selected.isEmpty)
                }
            }
        }
        .task { await requestAndLoad() }
    }

    private var title: String {
        let base = "All " + model.mediaType.pluralNoun
        return model.selected.isEmpty ? base : "\(base) (\(model.selected.count))"
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(section.assets, id: \.localIdentifier) { asset in
                                GalleryCell(
                                    asset: asset,
                                    isSelected: model.isSelected(asset)
                                )
                                .onTapGesture {
                                    HapticsManager.shared.selection()
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        model.toggle(asset)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                    } header: {
                        Text(section.title)
                            .font(FocalFont.rounded(17))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    /// Shown when the library holds nothing of this media type.
    ///
    /// Worth distinguishing from the denied state: access was granted and the
    /// fetch succeeded, there is simply nothing to pick. Without this the grid
    /// rendered as a blank sheet, which reads as a broken screen rather than an
    /// empty one.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: model.mediaType == .video
                  ? "video.slash"
                  : "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No \(model.mediaType.pluralNoun)")
                .font(FocalFont.rounded(20))

            if isLimited {
                // Not actually an empty library — the user shared a subset that
                // happens to contain none of this type. Telling them "no photos"
                // and nothing else would be misleading.
                Text("You've allowed access to selected \(model.mediaType.pluralNoun) only, "
                     + "and none are shared with this app yet.")
                    .font(FocalFont.rounded(15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Button("Manage Access") { MediaPermissions.openSettings() }
                    .font(FocalFont.rounded(17))
                    .buttonStyle(.pressable(scale: 0.95))
            } else {
                Text("Your library has no \(model.mediaType.pluralNoun) to import.")
                    .font(FocalFont.rounded(15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Photo library access is required to import \(model.mediaType.pluralNoun).")
                .font(FocalFont.rounded(15))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Open Settings") { MediaPermissions.openSettings() }
                .font(FocalFont.rounded(17))
                .buttonStyle(.pressable(scale: 0.95))
        }
        .padding(32)
    }

    // MARK: - Loading

    private func requestAndLoad() async {
        // `.task` re-runs on every appearance; a completed load stays put rather
        // than dropping back to a spinner.
        guard state != .loaded else { return }

        guard await MediaPermissions.requestPhotoLibrary() else {
            state = .denied
            return
        }

        isLimited = MediaPermissions.photoLibraryStatus() == .limited
        model.load()
        state = .loaded
    }
}

/// A single square thumbnail cell with a selection checkmark. Loads its image
/// lazily from the photo library.
private struct GalleryCell: View {

    package let asset: PHAsset
    package let isSelected: Bool

    @State private var image: UIImage?

    package var body: some View {
        // A plain square (no `GeometryReader`): the reader is greedy and lets the
        // cell's content and hit area spill past its square in a `LazyVGrid`, so
        // a tap could land on a neighbouring cell and toggle the wrong asset.
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .blue)
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: isSelected ? 3 : 0)
            )
            .scaleEffect(isSelected ? 0.96 : 1)
            // Make the whole square the tap target and clip the hit area to it,
            // so tapping anywhere on the image selects/deselects — and never
            // overflows onto an adjacent cell.
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                if image == nil { await load() }
            }
    }

    @MainActor
    private func load() async {
        // A fixed target sized for the three-column grid — no GeometryReader
        // needed just to pick a thumbnail resolution.
        let side = UIScreen.main.bounds.width / 3
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: side * scale, height: side * scale)

        let options = PHImageRequestOptions()
        // `.highQualityFormat` invokes the result handler exactly once, which is
        // what we need to safely bridge to a continuation.
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        image = await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: pixelSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                cont.resume(returning: result)
            }
        }
    }
}
