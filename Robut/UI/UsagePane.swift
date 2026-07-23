// UsagePane.swift — the panel under the menubar icon.
//
// One screenful, no scrolling, no tabs, no settings buried three levels
// down. Worst-pace window first, because that's the one that will bite.

import SwiftUI

struct UsagePane: View {
    @Bindable var model: AppModel
    /// Drives the countdown text without re-fetching anything.
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            usageContent
            Divider()
            footer
        }
        .frame(width: 300)
        .onReceive(tick) { now = $0 }
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var usageContent: some View {
        Group {
            if model.allWindows.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.allWindows) { window in
                        WindowRow(
                            window: window,
                            verdict: model.verdicts[window.id],
                            now: now
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if !model.unavailable.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.unavailable, id: \.provider) { entry in
                        UnavailableRow(provider: entry.provider, state: entry.state)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RobotFace(mood: model.mood, size: 18)
            Text("Robut").font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No usage data yet")
                .font(.system(size: 12, weight: .medium))
            Text("Robut reads Codex usage from local session files. Use Codex once and it'll show up here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // retryNow, not refresh: an explicit click is the user action
            // that clears a back-off.
            Button("Refresh") { Task { await model.retryNow() } }
                .buttonStyle(.link)
                .font(.system(size: 11))

            if let last = model.lastRefresh {
                Text("updated \(PaceFormatting.duration(now.timeIntervalSince(last))) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// One usage window: what it is, how full, and — the point — the verdict.
private struct WindowRow: View {
    let window: UsageWindow
    let verdict: PaceVerdict?
    let now: Date

    private var mood: RobotMood { RobotMood(outlook: verdict?.outlook) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(window.provider.displayName) · \(window.label)")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(PaceFormatting.percent(window.usedFraction))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }

            ProgressView(value: window.usedFraction)
                .progressViewStyle(.linear)
                .tint(mood.tint)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verdict.map(PaceFormatting.verdictText) ?? "Measuring pace…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(mood == .dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(mood.tint))
                Spacer()
                Text(PaceFormatting.resetText(for: window, now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let detail = verdict.flatMap(PaceFormatting.detailText) {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

/// A provider that can't be read right now. Muted, never alarming — this
/// is information, not an interruption.
private struct UnavailableRow: View {
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
            Circle().frame(width: 5, height: 5).foregroundStyle(.tertiary)
            Text(provider.displayName).font(.system(size: 11, weight: .medium))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
    }
}
