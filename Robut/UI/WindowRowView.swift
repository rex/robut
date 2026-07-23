// WindowRowView.swift — the provider group and the per-window listing unit.
//
// A group names the provider once (small mono caps) with a worst-case badge;
// each window under it shows its label + %, the SegmentMeter (carrying the
// pace marker), and the answer-first verdict line. Mirrors the Robut Design
// System's ProviderGroup / WindowRow.

import SwiftUI

struct ProviderGroupView: View {
    let group: ProviderUsageGroup
    let verdicts: [String: PaceVerdict]
    let now: Date

    private var worstMood: RobotMood { RobotMood(outlook: group.worstOutlook) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.provider.displayName.uppercased())
                    .font(RobutFont.mono(10, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                StatusBadge(text: PaceFormatting.badgeLabel(group.worstOutlook),
                            mood: worstMood)
            }
            .padding(.top, 11)
            .padding(.bottom, 9)

            VStack(alignment: .leading, spacing: Theme.Metrics.rowGap) {
                ForEach(group.windows) { window in
                    WindowRowView(window: window, verdict: verdicts[window.id], now: now)
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, Theme.Metrics.padX)
    }
}

struct WindowRowView: View {
    let window: UsageWindow
    let verdict: PaceVerdict?
    let now: Date

    private var mood: RobotMood { RobotMood(outlook: verdict?.outlook) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(RobutFont.ui(11, .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(PaceFormatting.percent(window.usedFraction))
                    .font(RobutFont.mono(11, .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            SegmentMeter(
                value: window.usedFraction,
                mood: mood,
                glow: mood != .calm,
                pace: window.elapsedFraction(now: now)
            )

            verdictLine
        }
    }

    private var verdictColor: Color {
        mood == .dim ? Theme.Colors.textSecondary : Theme.status(mood)
    }

    @ViewBuilder
    private var verdictLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verdict.map(PaceFormatting.verdictText) ?? "Measuring pace…")
                    .font(RobutFont.ui(11, .medium))
                    .foregroundStyle(verdictColor)
                Spacer()
                Text(PaceFormatting.resetText(for: window, now: now))
                    .font(RobutFont.ui(10))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if let detail = verdict.flatMap(PaceFormatting.detailText) {
                Text(detail)
                    .font(RobutFont.mono(10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
}

struct UnavailableRowView: View {
    let provider: Provider
    let state: ProviderState

    private var message: String {
        switch state {
        case .loading: "checking…"
        case .notConfigured: "not set up on this Mac"
        case .failed(let reason, _): reason
        case .ready: ""
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(mood: .dim, size: 5)
            Text(provider.displayName)
                .font(RobutFont.ui(11, .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(RobutFont.ui(10))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
    }
}
