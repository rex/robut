// UsagePane.swift — the panel under the menubar icon.
//
// One screenful, no scrolling, worst-pace window first. A stylized,
// provider-grouped rethink of the original sparse list (Robut Design System,
// ui_kits/menubar): an answer-first summary headline, a mood-tinted glow
// wash, provider groups with a worst-case badge, retro SegmentMeters, and the
// answer-first verdict per window.

import SwiftUI

struct UsagePane: View {
    @Bindable var model: AppModel
    /// Drives the countdown text without re-fetching anything.
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                mood: model.mood,
                summary: model.summaryText,
                isRefreshing: model.isRefreshing
            )
            content
            hairline
            footer
        }
        .frame(width: Theme.Metrics.paneWidth)
        .background {
            ZStack(alignment: .top) {
                Theme.Colors.panel
                glowWash
            }
        }
        .onReceive(tick) { now = $0 }
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if model.providerGroups.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.providerGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { hairline.padding(.vertical, 2) }
                    ProviderGroupView(group: group, verdicts: model.verdicts, now: now)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, Theme.Metrics.padY)
        }

        if !model.unavailable.isEmpty {
            hairline
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.unavailable, id: \.provider) { entry in
                    UnavailableRowView(provider: entry.provider, state: entry.state)
                }
            }
            .padding(.horizontal, Theme.Metrics.padX)
            .padding(.vertical, Theme.Metrics.footerPad)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No usage data yet")
                .font(RobutFont.ui(12, .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Robut reads Codex usage from local session files. "
                 + "Use Codex once and it'll show up here.")
                .font(RobutFont.ui(11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Metrics.padX)
        .padding(.vertical, Theme.Metrics.padY)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // retryNow, not refresh: an explicit click is the user action
            // that clears a back-off.
            Button("Refresh") { Task { await model.retryNow() } }
                .buttonStyle(.link)
                .font(RobutFont.ui(11, .medium))

            if let last = model.lastRefresh {
                Text("updated \(PaceFormatting.duration(now.timeIntervalSince(last))) ago")
                    .font(RobutFont.ui(10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(RobutFont.ui(11, .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Metrics.padX)
        .padding(.vertical, Theme.Metrics.footerPad)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
    }

    /// A faint radial halo in the worst-case status colour at the top of the
    /// panel, so the signal reads even peripherally. Hidden when dim.
    @ViewBuilder
    private var glowWash: some View {
        if model.mood != .dim {
            RadialGradient(
                colors: [Theme.status(model.mood).opacity(0.20), .clear],
                center: UnitPoint(x: 0.18, y: -0.1),
                startRadius: 0,
                endRadius: 190
            )
            .frame(height: 96)
            .allowsHitTesting(false)
        }
    }
}
