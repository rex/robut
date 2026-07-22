// Log.swift — the os.Logger namespace.
//
// Every module logs via Log.<category>. No print().
//
// PUBLIC REPO / privacy: never log file paths, account identifiers, tokens,
// or anything else that identifies the person running Robut. Log shapes and
// counts, not contents. When an identifier genuinely helps correlate, run
// it through `redactID(_:)`.

import Foundation
import os

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.robut.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let providers = Logger(subsystem: subsystem, category: "providers")
    static let pace = Logger(subsystem: subsystem, category: "pace")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Hash an identifier, keeping a short suffix so it stays correlatable
    /// across log lines without being reversible.
    static func redactID(_ id: String, keep: Int = 4) -> String {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(byte) }
        return String(format: "%llx-%@", hash, String(id.suffix(keep)))
    }
}
