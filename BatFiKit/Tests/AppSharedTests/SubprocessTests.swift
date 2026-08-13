//
//  SubprocessTests.swift
//  BatFi
//
//  Unit tests for the posix_spawn-backed subprocess helper.
//

import Foundation
import Testing

@testable import Shared

@Suite struct SubprocessTests {
    @Test func capturesStandardOutput() async {
        let output = await Subprocess.standardOutput(of: "/bin/echo", arguments: ["hello"], timeout: .seconds(10))
        #expect(output == "hello\n")
    }

    /// The regression this helper exists for (Sentry BATFI-7Q/7J/7P, 22 users).
    ///
    /// The old implementation used `Process`, whose `run()` looks catchable but is not:
    /// when the underlying `posix_spawn` fails, `-[NSConcreteTask launchWithDictionary:error:]`
    /// **raises an ObjC `NSInternalInconsistencyException`** ("Couldn't posix_spawn: error 35",
    /// i.e. `EAGAIN`), which walks straight past `do { try process.run() } catch { return nil }`
    /// and terminates the app.
    ///
    /// `posix_spawn` reports every such failure as a return code instead. This test drives
    /// that path with `ENOENT`; `EAGAIN` comes back through the exact same `guard` and is
    /// therefore covered by the same code, which is as close as a unit test can get —
    /// exhausting the process table on purpose would take the test runner down with it.
    @Test func returnsNilWhenTheExecutableDoesNotExist() async {
        let output = await Subprocess.standardOutput(
            of: "/nonexistent/definitely-not-here",
            timeout: .seconds(10)
        )
        #expect(output == nil)
    }

    @Test func returnsNilWhenTheCommandExitsNonZero() async {
        let output = await Subprocess.standardOutput(of: "/usr/bin/false", timeout: .seconds(10))
        #expect(output == nil)
    }

    @Test func ignoresStandardError() async {
        let output = await Subprocess.standardOutput(
            of: "/bin/sh",
            arguments: ["-c", "echo out; echo boom >&2"],
            timeout: .seconds(10)
        )
        #expect(output == "out\n")
    }

    /// A child writing more than the ~64KB pipe buffer blocks until someone drains it. Read
    /// before reaping, or this deadlocks: the child waits for buffer space, the parent waits
    /// for the child.
    @Test func readsOutputLargerThanThePipeBuffer() async {
        let output = await Subprocess.standardOutput(
            of: "/bin/sh",
            arguments: ["-c", "yes abcdefgh | head -n 20000"],
            timeout: .seconds(30)
        )
        #expect(output?.count == 20000 * 9)
    }

    /// The deadline must be enforced by SIGTERM, not by the SIGKILL grace that backs it up.
    ///
    /// Both paths return `nil`, so timing is the only thing that tells them apart — hence
    /// the bound below sits under the 2s grace. It is not a performance assertion: it
    /// caught the child inheriting an ignored SIGTERM from the host process, which left
    /// every timeout taking grace + timeout instead of timeout.
    @Test func returnsNilPromptlyWhenTheProcessOutlivesTheTimeout() async {
        let start = ContinuousClock.now
        let output = await Subprocess.standardOutput(
            of: "/bin/sleep",
            arguments: ["30"],
            timeout: .milliseconds(300)
        )
        let elapsed = ContinuousClock.now - start
        #expect(output == nil)
        #expect(elapsed < .seconds(2))
    }
}
