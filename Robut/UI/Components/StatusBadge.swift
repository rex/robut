// StatusBadge.swift — the compact status chip and its atom, the StatusDot.
//
// The badge sits on each provider-group header, showing that provider's
// worst-case pace at a glance ("tight", "runs dry early") in the status
// colour, tinted soft. Never alarming — information, not an interruption.

import SwiftUI

struct StatusDot: View {
    var mood: RobotMood
    var size: CGFloat = 5

    var body: some View {
        Circle()
            .fill(Theme.status(mood))
            .frame(width: size, height: size)
    }
}

struct StatusBadge: View {
    var text: String
    var mood: RobotMood

    var body: some View {
        HStack(spacing: 4) {
            StatusDot(mood: mood, size: 5)
            Text(text).font(RobutFont.ui(10, .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        .foregroundStyle(textColor)
    }

    private var fill: Color { Theme.status(mood).opacity(0.14) }
    private var stroke: Color { Theme.status(mood).opacity(mood == .dim ? 0.28 : 0.34) }

    private var textColor: Color {
        mood == .dim ? Theme.Colors.textSecondary : Theme.status(mood)
    }
}
