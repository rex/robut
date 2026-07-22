// ClaudeCLI.swift — asking the `claude` CLI about itself.
//
// Used ONLY to tell three states apart: Claude Code isn't installed,
// it's installed but signed out, or it's signed in and Robut just needs
// a token. That distinction is what lets an unconfigured machine show a
// calm "not set up" row instead of an error.
//
// PRIVACY: `claude auth status --json` includes the account email, org
// id and org name. Robut reads `loggedIn` and `subscriptionType` and
// discards the rest — none of it is ever logged, persisted, or shown.

import Foundation

enum ClaudeCLI {

    struct AuthStatus: Sendable {
        let loggedIn: Bool
        /// e.g. "max" / "pro". Display only; never used for logic, since
        /// the strings aren't stable.
        let subscriptionType: String?
    }

    /// GUI apps don't inherit a shell PATH, so `claude` has to be found
    /// by looking where it actually installs.
    static let candidatePaths: [String] = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
        "\(NSHomeDirectory())/.claude/local/claude",
        "/usr/bin/claude",
    ]

    static func executableURL() -> URL? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static var isInstalled: Bool { executableURL() != nil }

    /// nil when the CLI is absent or the call failed. Never throws at the
    /// caller: an unavailable CLI is a state, not an error.
    static func authStatus(timeout: TimeInterval = 10) async -> AuthStatus? {
        guard let executable = executableURL() else { return nil }
        guard let output = await run(executable, arguments: ["auth", "status", "--json"],
                                     timeout: timeout) else { return nil }
        guard let data = output.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawAuthStatus.self, from: data)
        else { return nil }

        return AuthStatus(loggedIn: raw.loggedIn ?? false,
                          subscriptionType: raw.subscriptionType)
    }

    /// Only the two fields Robut is allowed to care about. Everything
    /// else in the payload is personal data and is deliberately not
    /// modelled, so it cannot be accidentally logged later.
    private struct RawAuthStatus: Decodable {
        let loggedIn: Bool?
        let subscriptionType: String?
    }

    // MARK: - Process

    /// Run a short-lived command, returning stdout. Kills it on timeout so
    /// a wedged CLI can never wedge Robut.
    private static func run(
        _ executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Non-interactive: never let the CLI open a browser or try to
        // draw a TUI from inside a menubar app.
        var environment = ProcessInfo.processInfo.environment
        environment["CI"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }

        // Process and FileHandle predate Sendable; the box makes the
        // cross-queue capture explicit rather than implicit.
        let box = UncheckedBox((process: process, handle: pipe.fileHandleForReading))
        let resumed = AtomicFlag()

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let resumeOnce: @Sendable (String?) -> Void = { value in
                guard resumed.testAndSet() == false else { return }
                continuation.resume(returning: value)
            }

            // Watchdog, so a wedged CLI can never wedge Robut. No
            // DispatchWorkItem to cancel — the `isRunning` check makes a
            // late fire a no-op, and a cancellable item would be one more
            // non-Sendable capture for nothing.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                let running = box.value.process
                if running.isRunning { running.terminate() }
            }

            DispatchQueue.global().async {
                let data = box.value.handle.readDataToEndOfFile()
                let running = box.value.process
                running.waitUntilExit()
                guard running.terminationStatus == 0 else { resumeOnce(nil); return }
                resumeOnce(String(data: data, encoding: .utf8))
            }
        }
    }
}

/// Explicit escape hatch for Foundation types that predate `Sendable`.
/// Safe here: the wrapped value is only read, and `Process` tolerates
/// `terminate()` / `waitUntilExit()` from another queue.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Guarantees a continuation resumes exactly once — resuming twice is
/// undefined behaviour, not a warning.
private final class AtomicFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    /// Returns the previous value and sets it to true.
    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let previous = flag
        flag = true
        return previous
    }
}
