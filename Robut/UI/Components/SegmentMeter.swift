// SegmentMeter.swift — the pixel-native usage meter.
//
// A row of discrete blocks that fill like an 8-bit battery (Robut Design
// System — an intentional lean into the retro identity; it reads even faster
// than a smooth bar). An optional PACE MARKER draws the "safe pace" tick:
// where the fill *would* be if usage were perfectly even across the window
// and landed at exactly empty on reset. Fill left of the tick = under budget;
// right of it = burning too fast.

import SwiftUI

struct SegmentMeter: View {
    var value: Double
    var mood: RobotMood
    var segments: Int = 24
    var height: CGFloat = 7
    var gap: CGFloat = 2
    var glow: Bool = false
    /// 0...1 position of the even-pace tick; nil hides it.
    var pace: Double?

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<segments, id: \.self) { index in
                block(on: index < filled)
            }
        }
        .frame(height: height)
        .animation(Theme.Motion.bar, value: filled)
        .overlay { marker }
        .accessibilityElement()
        .accessibilityLabel("Usage")
        .accessibilityValue(percentLabel)
    }

    private var clampedValue: Double { max(0, min(1, value)) }
    private var filled: Int { Int((clampedValue * Double(segments)).rounded()) }
    private var percentLabel: String { "\(Int((clampedValue * 100).rounded())) percent" }

    private func block(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.block)
            .fill(on ? Theme.status(mood) : Theme.Colors.track)
            .shadow(color: glowColor(on: on), radius: 3)
    }

    private func glowColor(on: Bool) -> Color {
        glow && on ? Theme.status(mood).opacity(0.55) : .clear
    }

    @ViewBuilder
    private var marker: some View {
        if let pace {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.textPrimary.opacity(0.55))
                    .frame(width: 2, height: height + 2)
                    .position(x: markerX(pace, width: geo.size.width), y: height / 2)
            }
        }
    }

    private func markerX(_ pace: Double, width: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, pace))) * width
    }
}
