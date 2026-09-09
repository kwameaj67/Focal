//
//  MediaGalleryScreen.swift
//  PurpleWaveCameraCore
//


import Photos
import SwiftUI

package struct MediaGalleryScreen: View {

    @StateObject private var model: MediaGalleryModel

    /// Called with the final selection when the user taps Done.
    package let onDone: ([PHAsset]) -> Void
    /// Called when the user cancels.
    package let onCancel: () -> Void

    @State private var permissionDenied = false

    package init(
        mediaType: GalleryMediaType,
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
                if permissionDenied {
                    deniedState
                } else {
                    grid
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(model.selected) }
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
                            .font(.headline)
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

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Photo library access is required to import \(model.mediaType.pluralNoun).")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Open Settings") { MediaPermissions.openSettings() }
        }
        .padding(32)
    }

    // MARK: - Loading

    private func requestAndLoad() async {
        let granted = await MediaPermissions.requestPhotoLibrary()
        if granted {
            model.load()
        } else {
            permissionDenied = true
        }
    }
}

/// A single thumbnail cell with a selection checkmark. Loads its image lazily
/// from the photo library and cancels the request when it scrolls away.
private struct GalleryCell: View {

    package let asset: PHAsset
    package let isSelected: Bool

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    package var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                thumbnail(size: geo.size)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .blue)
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue, lineWidth: isSelected ? 3 : 0)
            )
            .scaleEffect(isSelected ? 0.96 : 1)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func thumbnail(size: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Color(.secondarySystemBackground)
                .task { await load(targetSize: size) }
        }
    }

    @MainActor
    private func load(targetSize: CGSize) async {
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)

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
