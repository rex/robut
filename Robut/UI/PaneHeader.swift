// PaneHeader.swift — the pane's top edge.
//
// The robot (whose colour is the whole at-a-glance signal), the wordmark, a
// live refresh spinner, and — the point — the answer-first SUMMARY line:
// worst-case across every window, calm-worded. The mood-tinted glow wash
// behind it lives in UsagePane so it can bleed across the panel.

import SwiftUI

struct PaneHeader: View {
    var mood: RobotMood
    var summary: String
    var isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                RobotFace(mood: mood, size: 22)
                    .shadow(color: Theme.status(mood).opacity(0.7), radius: 5)
                Text("Robut")
                    .font(RobutFont.ui(13, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            Text(summary)
                .font(RobutFont.ui(12, .medium))
                .foregroundStyle(summaryColor)
        }
        .padding(.horizontal, Theme.Metrics.padX)
        .padding(.top, Theme.Metrics.headerTop)
        .padding(.bottom, Theme.Metrics.headerBottom)
    }

    private var summaryColor: Color {
        mood == .dim ? Theme.Colors.textSecondary : Theme.status(mood)
    }
}
