//
//  CategoryScrollBar.swift
//  FocalCore
//
//  The horizontal, centre-snapping category selector shown above the shutter on
//  the photo screen (the "Sticker / Profile / Walk Around" row). A SwiftUI
//  reimplementation of a horizontal, camera-mode-dial-style selector.
//
//  Selection advances one category per horizontal swipe (like the native camera
//  mode dial); tapping a pill jumps straight to it. The selected pill is always
//  centred.
//

import SwiftUI

package struct CategoryScrollBar: View {

    package let categories: [FCCategory]
    @Binding package var selected: FCCategory?

    /// Rotation applied so labels stay upright as the device rotates.
    package var rotation: Double = 0

    /// Minimum horizontal travel before a swipe changes the selection.
    private let swipeThreshold: CGFloat = 40

    package init(
        categories: [FCCategory],
        selected: Binding<FCCategory?>,
        rotation: Double = 0
    ) {
        self.categories = categories
        self._selected = selected
        self.rotation = rotation
    }

    package var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Leading/trailing spacers let the first and last pills
                    // reach the horizontal centre when selected.
                    Spacer(minLength: 120)
                    ForEach(categories) { category in
                        pill(for: category)
                            .id(category.id)
                            .onTapGesture { select(category, proxy: proxy) }
                    }
                    Spacer(minLength: 120)
                }
                .padding(.vertical, 6)
            }
            // Disable free scrolling so the bar behaves like a discrete dial:
            // positioning is driven programmatically, selection by swipe.
            .scrollDisabled(true)
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        if value.translation.width <= -swipeThreshold {
                            move(by: 1, proxy: proxy)      // swipe left → next
                        } else if value.translation.width >= swipeThreshold {
                            move(by: -1, proxy: proxy)     // swipe right → previous
                        }
                    }
            )
            .onAppear { center(on: selected, proxy: proxy, animated: false) }
            .onChange(of: selected) { _, newValue in
                center(on: newValue, proxy: proxy, animated: true)
            }
        }
        .frame(height: 44)
    }

    // MARK: - Pieces

    private func pill(for category: FCCategory) -> some View {
        let isSelected = category.id == selected?.id
        return Text(category.title)
            .font(FocalFont.rounded(14))
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isSelected ? Color.white : Color.clear)
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func select(_ category: FCCategory, proxy: ScrollViewProxy) {
        guard category.id != selected?.id else { return }
        selected = category  // `onChange` re-centres
        HapticsManager.shared.selection()
    }

    /// Advances the selection by `delta` categories, clamped to the ends.
    private func move(by delta: Int, proxy: ScrollViewProxy) {
        guard let current = selected ?? categories.first,
              let index = categories.firstIndex(where: { $0.id == current.id }) else { return }
        let target = min(max(index + delta, 0), categories.count - 1)
        guard target != index else { return }
        selected = categories[target]  // `onChange` re-centres
        HapticsManager.shared.selection()
    }

    private func center(on category: FCCategory?, proxy: ScrollViewProxy, animated: Bool) {
        guard let id = category?.id else { return }
        let scroll = { proxy.scrollTo(id, anchor: .center) }
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { scroll() }
        } else {
            scroll()
        }
    }
}

// MARK: - Previews

#Preview("Category bar") {
    @Previewable @State var selected: FCCategory? = FCCategory("Profile")
    ZStack {
        Color.black
        CategoryScrollBar(
            categories: [
                FCCategory("Profile"),
                FCCategory("Sticker"),
                FCCategory("Walk Around"),
                FCCategory("Engine")
            ],
            selected: $selected
        )
    }
    .ignoresSafeArea()
}

#Preview("Category bar — single option") {
    // With one category there's nothing to swipe between; the pill should still
    // centre rather than sitting flush left.
    @Previewable @State var selected: FCCategory? = FCCategory("Profile")
    ZStack {
        Color.black
        CategoryScrollBar(categories: [FCCategory("Profile")], selected: $selected)
    }
    .ignoresSafeArea()
}
