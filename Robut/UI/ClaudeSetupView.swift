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
                Robut signs in with its own token, so macOS never asks for \
                your keychain password and it never reads Claude Code's \
                credentials.
                """)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch step {
            case .start: startStep
            case .awaitingCode: codeStep
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.hasClaudeToken {
                Button("Sign out of Claude", role: .destructive) {
                    model.signOutClaude()
                    onDone()
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack {
            Text("Connect Claude").font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.link)
                .font(.system(size: 11))
        }
    }

    private var startStep: some View {
        Button {
            openSignIn()
        } label: {
            Label("Sign in with Claude", systemImage: "person.badge.key")
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .keyboardShortcut(.defaultAction)
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your browser opened. Authorize, copy the code it shows, then paste it here:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // A paste button needs no text-field focus, so the panel can't
            // dismiss out from under it. Typing stays available too.
            HStack(spacing: 6) {
                Button {
                    pastedCode = NSPasteboard.general.string(forType: .string) ?? ""
                    submit()
                } label: {
                    Label("Paste code", systemImage: "clipboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .controlSize(.small)
                .disabled(working)

                Button("Re-open browser") { openSignIn() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .disabled(working)
            }

            HStack(spacing: 6) {
                SecureField("or paste code here", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(working)
                Button("Submit") { submit() }
                    .controlSize(.small)
                    .disabled(working || pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if working {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Completing sign-in…").font(.system(size: 10)).foregroundStyle(.secondary)
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
