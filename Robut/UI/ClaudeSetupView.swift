// ClaudeSetupView.swift — one-time Claude setup, INLINE in the pane.
//
// WHY THIS IS NOT A SHEET, so nobody "improves" it back into one:
//
// `MenuBarExtra` with `.menuBarExtraStyle(.window)` is an NSPanel that
// closes the moment it resigns key. Presenting a sheet from it makes the
// sheet key, so the panel resigns, so the panel closes — taking the
// sheet with it. The symptom is that clicking the text field makes the
// entire UI vanish. Robut is also `LSUIElement`, so the app isn't active
// and can't readily take keyboard focus for a sheet anyway.
//
// So: rendered inline, and the PRIMARY action is a clipboard paste that
// needs no text-field focus at all. The secure field stays as a fallback
// for anyone who'd rather type.
//
// The token goes straight into Robut's own keychain item. It is never
// logged, never written to a file, and never redisplayed.

import AppKit
import SwiftUI

struct ClaudeSetupView: View {
    @Bindable var model: AppModel
    let onDone: () -> Void

    @State private var typed = ""
    @State private var status: Status?

    private enum Status: Equatable {
        case saved
        case empty
        case looksWrong

        var message: String {
            switch self {
            case .saved: "Saved — checking usage…"
            case .empty: "Clipboard is empty"
            case .looksWrong: "That doesn't look like a token"
            }
        }

        var isError: Bool { self != .saved }
    }

    private let command = "claude setup-token"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connect Claude").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }

            Text("""
                Robut uses its own token, so macOS never asks for your \
                keychain password. Run this, copy the result, then click \
                Paste:
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))

                Button {
                    copy(command)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy command")
            }

            // Primary path: needs no keyboard focus, so the panel can't
            // dismiss out from under it.
            Button {
                saveFromClipboard()
            } label: {
                Label("Paste token from clipboard", systemImage: "clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)

            DisclosureGroup {
                HStack(spacing: 6) {
                    SecureField("Paste or type token", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Button("Save") { save(typed) }
                        .controlSize(.small)
                        .disabled(typed.trimmed.isEmpty)
                }
                .padding(.top, 4)
            } label: {
                Text("Type it instead").font(.system(size: 10))
            }

            if let status {
                Text(status.message)
                    .font(.system(size: 10))
                    .foregroundStyle(status.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.green))
            }

            if model.hasClaudeToken {
                Button("Remove stored token", role: .destructive) {
                    model.clearClaudeToken()
                    status = nil
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }

            Text("Stored in Robut's own keychain item — never Claude Code's.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveFromClipboard() {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        guard !clipboard.trimmed.isEmpty else { status = .empty; return }
        save(clipboard)
    }

    private func save(_ raw: String) {
        let token = raw.trimmed
        // Loose sanity check only. Anthropic's token format isn't a
        // contract, so reject the obviously-wrong (a pasted command, a
        // sentence) without guessing at a prefix that may change.
        guard token.count >= 20, !token.contains(" "), !token.contains("\n") else {
            status = .looksWrong
            return
        }
        model.saveClaudeToken(token)
        typed = ""
        status = .saved
        onDone()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
