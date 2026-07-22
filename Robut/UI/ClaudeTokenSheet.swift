// ClaudeTokenSheet.swift — one-time Claude setup.
//
// Deliberately a paste field rather than a "Sign in" button. Anthropic's
// sanctioned way to mint a long-lived subscription token is
// `claude setup-token`; the browser alternative would mean presenting
// Claude Code's OAuth client id from a third-party app.
//
// The token goes straight from this field into Robut's own keychain
// item. It is never logged, never written to a file, and never shown
// again — `SecureField` keeps it off screen even while typing.

import SwiftUI

struct ClaudeTokenSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""

    private let command = "claude setup-token"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Claude")
                .font(.system(size: 13, weight: .semibold))

            Text("""
                Robut needs its own token so macOS never asks for your \
                keychain password. Run this in a terminal, then paste the \
                result:
                """)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy command")
            }

            SecureField("Paste token here", text: $token)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            Text("Stored in Robut's own keychain item. Robut never reads Claude Code's.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.hasClaudeToken {
                    Button("Remove", role: .destructive) {
                        model.clearClaudeToken()
                        dismiss()
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.saveClaudeToken(token)
                    token = ""
                    dismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
