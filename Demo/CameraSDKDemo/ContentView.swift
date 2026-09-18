//
//  ContentView.swift
//  CameraSDKDemo
//
//  Presents the two SDK screens and logs what comes back. Captured photos are
//  shown in a small strip so you can confirm the round-trip on device.
//

import SwiftUI
import CameraSDK

struct ContentView: View {

    @State private var showPhoto = false
    @State private var showVideo = false

    /// Most recent captures, newest first, for a simple on-screen confirmation.
    @State private var recentPhotos: [UIImage] = []
    @State private var lastVideo: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Button {
                    showPhoto = true
                } label: {
                    Label("Photo capture", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    showVideo = true
                } label: {
                    Label("Video recorder", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                }

                if !recentPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(recentPhotos.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                if let lastVideo {
                    Text("Last video: \(lastVideo)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .navigationTitle("CameraSDK Demo")
        }
        .fullScreenCover(isPresented: $showPhoto) {
            CSCameraScreen(
                config: CSCameraConfig(
                    categories: [
                        CSCategory(id: "AMKT", title: "Profile"),
                        CSCategory(id: "STICKER", title: "Sticker"),
                        CSCategory(id: "WALKAROUND", title: "Walk Around")
                    ],
                    startingCategoryID: "AMKT",
                    capturesLocation: true,
                    overlayLabel: "MO6759"
                ),
                handlers: CSPhotoHandlers(
                    onCapture: { result in
                        recentPhotos.insert(result.image, at: 0)
                        print("📷 captured \(result.category?.title ?? "-") from \(result.source)")
                        print("📷 at \(result.capturedAt)")
                        if let c = result.location?.coordinate {
                            print("📷 location \(c.latitude), \(c.longitude)")
                        } else {
                            print("📷 location unavailable")
                        }
                    },
                    onFinish: { _ in showPhoto = false }
                )
            )
        }
        .fullScreenCover(isPresented: $showVideo) {
            CSVideoScreen(
                config: CSVideoConfig(
                    categories: [
                        CSCategory("Driving"),
                        CSCategory("Functional"),
                        CSCategory("Engine")
                    ],
                    maxDuration: 180,
                    capturesLocation: true,
                    overlayLabel: "MO6759"
                ),
                handlers: CSVideoHandlers(
                    onRecord: { result in
                        lastVideo = "\(result.fileURL.lastPathComponent) (\(Int(result.duration))s)"
                        print("🎥 recorded \(result.fileURL.lastPathComponent)")
                        print("🎥 at \(result.capturedAt)              ")
                        if let c = result.location?.coordinate {
                            print("🎥 location \(c.latitude), \(c.longitude)")
                        } else {
                            print("🎥 location unavailable")
                        }
                    },
                    onFinish: { _ in showVideo = false }
                )
            )
        }
    }
}

