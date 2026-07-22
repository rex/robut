// RobutKeychain.swift — Robut's OWN keychain item. Nothing else.
//
// ┌───────────────────────────────────────────────────────────────────┐
// │ THE RULE THIS WHOLE APP EXISTS TO ENFORCE                          │
// │                                                                    │
// │ Robut reads ONLY keychain items it created itself. It must NEVER   │
// │ read another app's item — above all `Claude Code-credentials`.     │
// │                                                                    │
// │ macOS binds each keychain item to an ACL of trusted apps. Claude   │
// │ Code rewrites its credential on every token refresh, which resets  │
// │ that ACL — so any other app reading it gets a password prompt,     │
// │ forever, no matter how many times you click "Always Allow". That   │
// │ is the bug Robut was built to eliminate. An app is never prompted  │
// │ for an item it created, which is why this file is the only         │
// │ keychain surface in the codebase.                                  │
// └───────────────────────────────────────────────────────────────────┘

import Foundation
import Security

enum RobutKeychain {

    /// Namespaced under Robut's own bundle id so the item is
    /// unambiguously ours.
    static let service = "com.robut.app.tokens"

    enum Item: String {
        /// Long-lived Claude subscription token from `claude setup-token`.
        case claudeToken = "claude-token"
    }

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    // MARK: - Read

    /// Returns nil when absent. Never prompts: we created this item.
    static func read(_ item: Item) -> String? {
        var query = baseQuery(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func has(_ item: Item) -> Bool { read(item) != nil }

    // MARK: - Write

    /// Upsert. Never log the value — not even truncated.
    static func write(_ value: String, to item: Item) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { try delete(item); return }
        guard let data = trimmed.data(using: .utf8) else { return }

        let query = baseQuery(item)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        // AfterFirstUnlock so a background refresh works without the user
        // being present — but still never off a locked machine.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    // MARK: - Delete

    static func delete(_ item: Item) throws {
        let status = SecItemDelete(baseQuery(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Private

    private static func baseQuery(_ item: Item) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
    }
}
