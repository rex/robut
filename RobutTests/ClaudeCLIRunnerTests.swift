// ClaudeCLIRunnerTests.swift — the process runner can never hang the loop.
//
// A hung `run` froze the refresh loop for 19 hours (2026-09-04): the loop
// awaits every fetch. These pin the guarantee that `run` returns within
// its budget no matter what the child — or its orphans — does. /bin/sh
// stands in for the CLI; nothing here spawns `claude`.

import Foundation
import Testing

@testable import Robut

@Suite("Claude CLI runner")
struct ClaudeCLIRunnerTests {

    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test("A normal exit returns stdout")
    func returnsOutput() async {
        let output = await ClaudeCLI.run(shell, arguments: ["-c", "printf hello"], timeout: 5)
        #expect(output == "hello")
    }

    @Test("A non-zero exit is nil, never partial output")
    func failureIsNil() async {
        let output = await ClaudeCLI.run(shell, arguments: ["-c", "printf partial; exit 3"], timeout: 5)
        #expect(output == nil)
    }

    @Test("A child that never exits is terminated, and the call returns within budget")
    func hungChildIsBounded() async {
        let start = Date()
        let output = await ClaudeCLI.run(shell, arguments: ["-c", "sleep 30"], timeout: 1)
        #expect(output == nil)
        // timeout + the 3s kill grace, with slack for a busy machine.
        #expect(Date().timeIntervalSince(start) < 8)
    }

    @Test("A grandchild holding the pipe open cannot pin the call")
    func orphanHoldingPipeDoesNotBlock() async {
        // sh prints and exits at once; its backgrounded child keeps our
        // pipe's write end for 20s. A read-to-EOF would wait for it.
        let start = Date()
        let output = await ClaudeCLI.run(
            shell, arguments: ["-c", "sleep 20 >/dev/null & printf done"], timeout: 10
        )
        #expect(output == "done")
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test("A grandchild inheriting stdout still cannot pin the call")
    func orphanInheritingStdoutDoesNotBlock() async {
        let start = Date()
        let output = await ClaudeCLI.run(shell, arguments: ["-c", "sleep 20 & printf done"], timeout: 10)
        #expect(output == "done")
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
