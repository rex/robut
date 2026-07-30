// ClaudeSetupView.swift — full-scope Claude sign-in, INLINE in the pane.
//
// WHY INLINE, NOT A SHEET: `MenuBarExtra(.window)` is an NSPanel that
// closes the moment it resigns key, so a sheet taking focus dismisses the
// whole panel. Rendered inline instead. (Learned the hard way — see the
// git history.)
//
// The flow: "Sign in with Claude" opens the browser to the PKCE authorize
// URL; the browser shows a code; the user pastes it back. That yields a
// FULL-SCOPE token (with user:profile) — which a `claude setup-token`
// deliberately can't provide, and which the usage endpoint requires. The
// token lands in Robut's own keychain item and is never shown again.

import AppKit
import SwiftUI

struct ClaudeSetupView: View {
    @Bindable var model: AppModel
    let onDone: () -> Void

    @State private var step: Step = .start
    @State private var pastedCode = ""
    @State private var error: String?
    @State private var working = false

    private enum Step { case start, awaitingCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text("""
                Precise, live usage straight from Anthropic. Robut signs in \
                with its own token — it never reads Claude Code's credentials.
                """)
                .font(RobutFont.ui(11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            switch step {
            case .start: startStep
            case .awaitingCode: codeStep
            }

            if let error {
                Text(error)
                    .font(RobutFont.ui(10))
                    .foregroundStyle(Theme.status(.alarmed))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.claudeConnected {
                Button("Sign out of Claude", role: .destructive) {
                    model.signOutClaude()
                    onDone()
                }
                .buttonStyle(.link)
                .font(RobutFont.ui(10))
            }
        }
        .padding(.horizontal, Theme.Metrics.padX)
        .padding(.vertical, Theme.Metrics.padY)
    }

    private var header: some View {
        HStack {
            Text("Connect Claude")
                .font(RobutFont.ui(12, .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.link)
                .font(RobutFont.ui(11))
        }
    }

    private var startStep: some View {
        Button {
            openSignIn()
        } label: {
            Label("Sign in with Claude", systemImage: "person.badge.key")
                .font(RobutFont.ui(11, .medium))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .keyboardShortcut(.defaultAction)
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your browser opened. Authorize, copy the code it shows, then paste it here:")
                .font(RobutFont.ui(11))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // A paste button needs no text-field focus, so the panel can't
            // dismiss out from under it. Typing stays available too.
            HStack(spacing: 6) {
                Button {
                    pastedCode = NSPasteboard.general.string(forType: .string) ?? ""
                    submit()
                } label: {
                    Label("Paste code", systemImage: "clipboard")
                        .font(RobutFont.ui(11, .medium))
                }
                .controlSize(.small)
                .disabled(working)

                Button("Re-open browser") { openSignIn() }
                    .buttonStyle(.link)
                    .font(RobutFont.ui(10))
                    .disabled(working)
            }

            HStack(spacing: 6) {
                SecureField("or paste code here", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .font(RobutFont.mono(11))
                    .disabled(working)
                Button("Submit") { submit() }
                    .controlSize(.small)
                    .disabled(working || pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if working {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Completing sign-in…")
                        .font(RobutFont.ui(10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func openSignIn() {
        error = nil
        guard let url = model.beginClaudeSignIn() else {
            error = "Couldn't build the sign-in link"
            return
        }
        NSWorkspace.shared.open(url)
        step = .awaitingCode
    }

    private func submit() {
        let code = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        working = true
        error = nil
        Task {
            let failure = await model.completeClaudeSignIn(pastedCode: code)
            working = false
            pastedCode = ""
            if let failure {
                error = failure
            } else {
                onDone()
            }
        }
    }
}
