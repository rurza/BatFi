//
//  HelperOwnershipTests.swift
//  BatFi
//
//  The comparison that decides whether the app is about to cost the user a System Settings
//  approval. Both directions matter: missing a foreign helper leaves the app driving
//  nothing, and inventing one takes down a working install.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct HelperOwnershipTests {
    private let ours = "/Applications/BatFi.app/Contents/MacOS/BatFiHelper"
    private let theirs = "/Users/adam/Downloads/BatFi.app/Contents/MacOS/BatFiHelper"

    private func identity(_ path: String, cdHash: String? = "abc123", version: String? = "99999") -> HelperCodeIdentity {
        HelperCodeIdentity(executablePath: path, cdHash: cdHash, version: version, processIdentifier: 42)
    }

    @Test("The helper this copy ships is our own")
    func matchingPathAndHashIsOurs() {
        let ownership = HelperOwnershipCheck.evaluate(
            running: identity(ours),
            expectedExecutablePath: ours,
            expectedCDHash: "abc123"
        )

        #expect(ownership == .ours)
    }

    @Test("A helper from another bundle is foreign, and names the app that owns it")
    func otherBundleIsForeign() {
        let ownership = HelperOwnershipCheck.evaluate(
            running: identity(theirs),
            expectedExecutablePath: ours,
            expectedCDHash: "abc123"
        )

        guard case let .foreign(conflict) = ownership else {
            Issue.record("Expected a conflict, got \(ownership)")
            return
        }
        #expect(conflict.kind == .otherBundle)
        #expect(conflict.owningAppPath == "/Users/adam/Downloads/BatFi.app")
        #expect(conflict.runningExecutablePath == theirs)
    }

    /// The case a path comparison cannot see: the app was replaced underneath a helper that
    /// is still running, so the right file is at the right place and the wrong code is in
    /// memory.
    @Test("A different build at our own path is a stale binary, not another bundle")
    func sameBundleDifferentBuildIsStale() {
        let ownership = HelperOwnershipCheck.evaluate(
            running: identity(ours, cdHash: "old999"),
            expectedExecutablePath: ours,
            expectedCDHash: "new111"
        )

        guard case let .foreign(conflict) = ownership else {
            Issue.record("Expected a conflict, got \(ownership)")
            return
        }
        #expect(conflict.kind == .staleBinary)
    }

    /// A missing hash on either side is an unreadable signature, not evidence of a mismatch.
    /// Reporting a conflict here would quit and re-register the helper on machines where the
    /// hash simply could not be read.
    @Test("An unreadable hash never manufactures a conflict")
    func unknownHashesDoNotAccuse() {
        #expect(HelperOwnershipCheck.evaluate(
            running: identity(ours, cdHash: nil),
            expectedExecutablePath: ours,
            expectedCDHash: "new111"
        ) == .ours)

        #expect(HelperOwnershipCheck.evaluate(
            running: identity(ours),
            expectedExecutablePath: ours,
            expectedCDHash: nil
        ) == .ours)
    }

    @Test("No identity at all is undetermined, never foreign")
    func missingIdentityIsUndetermined() {
        let ownership = HelperOwnershipCheck.evaluate(
            running: nil,
            expectedExecutablePath: ours,
            expectedCDHash: "abc123"
        )

        guard case .undetermined = ownership else {
            Issue.record("Expected undetermined, got \(ownership)")
            return
        }
    }

    /// `/private` is how the same file reaches us under two names — routinely, for anything
    /// running from a temporary directory or a mounted disk image. Comparing the raw strings
    /// would report the app's own helper as somebody else's.
    @Test("The /private prefix does not make a copy of itself foreign")
    func privatePrefixIsCanonicalised() {
        let ownership = HelperOwnershipCheck.evaluate(
            running: identity("/private/var/folders/x/BatFi.app/Contents/MacOS/BatFiHelper"),
            expectedExecutablePath: "/var/folders/x/BatFi.app/Contents/MacOS/BatFiHelper",
            expectedCDHash: "abc123"
        )

        #expect(ownership == .ours)
    }

    @Test("A trailing separator is not a difference")
    func trailingSlashIsCanonicalised() {
        #expect(HelperOwnershipCheck.canonicalize("/Applications/BatFi.app/") == "/Applications/BatFi.app")
    }

    @Test("An executable that is not inside an .app claims no owning bundle")
    func nonBundleExecutableHasNoOwningApp() {
        #expect(HelperOwnershipCheck.owningAppPath(forExecutableAt: "/usr/local/bin/BatFiHelper") == nil)
    }
}
