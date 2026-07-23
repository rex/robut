// ClaudeCLI.swift — locating and running the `claude` CLI.
//
// Robut spawns `claude` to read usage; the CLI authenticates itself
// against Claude Code's own credentials, so Robut holds none.

import Foundation

enum ClaudeCLI {

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

    // MARK: - Usage

    /// Raw output of `claude -p "/usage" --output-format json`.
    ///
    /// Runs in a temp directory so the probe picks up no project context,
    /// no CLAUDE.md, and no repo-specific config — this should be a
    /// question about the account, not about wherever Robut happens to
    /// have been launched from.
    static func usageOutput(timeout: TimeInterval = 45) async -> String? {
        guard let executable = executableURL() else { return nil }
        return await run(
            executable,
            arguments: ["-p", "/usage", "--output-format", "json"],
            timeout: timeout,
            workingDirectory: scratchDirectory()
        )
    }

    /// `--output-format json` wraps everything in a result envelope. Pull
    /// out the human-readable text; fall back to the raw string if the
    /// envelope shape isn't what we expect.
    static func resultText(fromJSONEnvelope output: String) -> String? {
        struct Envelope: Decodable {
            let result: String?
            let isError: Bool?
            enum CodingKeys: String, CodingKey {
                case result
                case isError = "is_error"
            }
        }
        guard let data = output.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let result = envelope.result
        else { return nil }
        return result
    }

    private static func scratchDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "robut-claude-probe", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Process

    /// Run a short-lived command, returning stdout. Kills it on timeout so
    /// a wedged CLI can never wedge Robut.
    private static func run(
        _ executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        workingDirectory: URL? = nil
    ) async -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
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
