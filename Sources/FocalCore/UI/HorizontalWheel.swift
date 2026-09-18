//
//  HorizontalWheel.swift
//  FocalCore
//
//  The horizontal scroll wheels used by the exposure and timer overlays.
//
//  Two variants because the underlying values differ in kind, and pretending
//  otherwise would make both worse:
//
//   • `DiscreteWheel` — a row of labelled stops that snap, for the timer.
//   • `ExposureWheel` — a continuous ruler with a fixed centre indicator, for
//     exposure bias, which is a float over a device-reported range.
//
//  Both tick haptically as the selection changes, which is what makes a wheel
//  feel like a wheel rather than a scroll view.
//

import SwiftUI

// MARK: - Discrete

/// A snapping row of options with a fixed centre indicator.
package struct DiscreteWheel<Value: Hashable>: View {

    private let values: [Value]
    private let title: (Value) -> String
    @Binding private var selection: Value

    /// Which option is currently under the centre indicator.
    ///
    /// Separate from `selection` on purpose: this tracks the scroll as it
    /// settles, and only then writes through. Binding the scroll straight to
    /// `selection` would fire the host's `onChange` for every option the wheel
    /// passes over during a flick.
    @State private var centered: Value?

    /// Width of one stop. The indicator matches it, so "what's framed" and
    /// "what's selected" can't disagree.
    private let stopWidth: CGFloat = 76

    package init(
        values: [Value],
        selection: Binding<Value>,
        title: @escaping (Value) -> String
    ) {
        self.values = values
        self._selection = selection
        self.title = title
    }

    package var body: some View {
        GeometryReader { geo in
            let sidePadding = max(0, (geo.size.width - stopWidth) / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(values, id: \.self) { value in
                        let isSelected = value == selection
                        Text(title(value))
                            .font(FocalFont.rounded(isSelected ? 17 : 15))
                            .foregroundColor(isSelected ? .yellow : .white.opacity(0.6))
                            .frame(width: stopWidth, height: 44)
                            .contentShape(Rectangle())
                            .id(value)
                            .onTapGesture {
                                guard value != selection else { return }
                                // Tapping is just a shortcut for scrolling there;
                                // moving `centered` drives the same path a drag
                                // takes, so both routes behave identically.
                                withAnimation(.easeOut(duration: 0.2)) { centered = value }
                            }
                    }
                }
                .scrollTargetLayout()
                // Half a viewport of padding on each side so the first and last
                // options can still reach the centre indicator.
                .padding(.horizontal, sidePadding)
            }
            // `.viewAligned` is what lets the wheel coast: the drag runs free and
            // the scroll view decelerates to the nearest stop rather than
            // stopping wherever the finger lifted.
            .scrollTargetBehavior(.viewAligned)
            // Reports whichever stop settled under the anchor. This is the piece
            // that was missing — the wheel snapped correctly but never told
            // anyone, so selection only ever changed by tapping.
            .scrollPosition(id: $centered, anchor: .center)
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
                    .frame(width: stopWidth, height: 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 56)
        .onAppear { centered = selection }
        .onChange(of: centered) { _, landed in
            guard let landed, landed != selection else { return }
            HapticsManager.shared.selection()
            selection = landed
        }
        .onChange(of: selection) { _, newValue in
            // Keeps the wheel honest when the value changes from outside — the
            // host resetting it, or the other control for the same setting.
            guard centered != newValue else { return }
            withAnimation(.easeOut(duration: 0.2)) { centered = newValue }
        }
    }
}

// MARK: - Continuous

/// A ruler-style exposure control. Dragging moves the scale under a fixed
/// centre indicator; the value is read off the centre.
package struct ExposureWheel: View {

    @Binding private var value: Float
    private let range: ClosedRange<Float>

    /// Points of travel per 1 EV. Sets how much drag it takes to cross the
    /// range — 40 gives a ±8 EV device about 640pt of travel, which is enough
    /// for fine adjustment without feeling sluggish.
    private let pointsPerEV: CGFloat = 40

    /// Value at the moment the current drag began.
    @State private var dragStart: Float?
    /// Last value we ticked on, so the haptic fires per step rather than per
    /// pixel of movement.
    @State private var lastTickedStep: Int?

    package init(value: Binding<Float>, range: ClosedRange<Float>) {
        self._value = value
        self.range = range
    }

    package var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f EV", value))
                .font(FocalFont.rounded(15))
                .foregroundColor(.yellow)
                .monospacedDigit()

            GeometryReader { geo in
                let mid = geo.size.width / 2
                ZStack {
                    ticks(width: geo.size.width, mid: mid)

                    // Fixed centre indicator: the scale moves, this doesn't.
                    Capsule()
                        .fill(Color.yellow)
                        .frame(width: 2, height: 28)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let start = dragStart ?? value
                            if dragStart == nil { dragStart = start }

                            // Drag left raises exposure, matching the way the
                            // scale slides under the indicator.
                            let delta = Float(-drag.translation.width / pointsPerEV)
                            let next = min(max(start + delta, range.lowerBound),
                                           range.upperBound)
                            value = next

                            // Tick once per third of an EV.
                            let step = Int((next * 3).rounded())
                            if step != lastTickedStep {
                                lastTickedStep = step
                                HapticsManager.shared.selection()
                            }
                        }
                        .onEnded { _ in
                            dragStart = nil
                            lastTickedStep = nil
                        }
                )
            }
            .frame(height: 44)

            Button("Reset") {
                guard value != 0 else { return }
                HapticsManager.shared.tap()
                withAnimation(.easeOut(duration: 0.15)) { value = 0 }
            }
            .font(FocalFont.rounded(12))
            .foregroundColor(.white.opacity(0.7))
            .buttonStyle(.pressable(scale: 0.95))
        }
        .padding(.horizontal, 16)
    }

    /// Ruler marks, drawn relative to the current value so the scale slides
    /// under the fixed indicator. A taller mark every whole EV.
    private func ticks(width: CGFloat, mid: CGFloat) -> some View {
        let step: Float = 1.0 / 3.0
        let count = Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1

        return ForEach(0..<max(count, 1), id: \.self) { i in
            let ev = range.lowerBound + Float(i) * step
            let offset = mid + CGFloat(ev - value) * pointsPerEV
            let isWhole = abs(ev.rounded() - ev) < 0.01

            if offset >= -8 && offset <= width + 8 {
                Capsule()
                    .fill(Color.white.opacity(isWhole ? 0.85 : 0.35))
                    .frame(width: isWhole ? 1.5 : 1, height: isWhole ? 18 : 10)
                    .position(x: offset, y: 22)
            }
        }
    }
}

// MARK: - Previews

// These controls sit on a live camera feed, so every preview is on black —
// previewing them on the default light canvas would misrepresent the contrast
// they actually have to survive.

#Preview("Discrete wheel — timer") {
    @Previewable @State var timer: FCCaptureTimer = .three
    ZStack {
        Color.black
        DiscreteWheel(
            values: FCCaptureTimer.allCases,
            selection: $timer,
            title: \.title
        )
    }
    .ignoresSafeArea()
}

#Preview("Discrete wheel — two options") {
    // The narrow case: with only two stops the side padding has to stretch far
    // enough that either end still reaches the centre indicator.
    @Previewable @State var isOn = true
    ZStack {
        Color.black
        DiscreteWheel(
            values: [true, false],
            selection: $isOn,
            title: { $0 ? "On" : "Off" }
        )
    }
    .ignoresSafeArea()
}

#Preview("Exposure wheel") {
    @Previewable @State var bias: Float = 0
    ZStack {
        Color.black
        ExposureWheel(value: $bias, range: -8...8)
    }
    .ignoresSafeArea()
}

#Preview("Exposure wheel — narrow device range") {
    // Not every device reports ±8. A front camera can offer far less, and the
    // ruler has to stay readable when the whole range fits on screen at once.
    @Previewable @State var bias: Float = 1.5
    ZStack {
        Color.black
        ExposureWheel(value: $bias, range: -2...2)
    }
    .ignoresSafeArea()
}
