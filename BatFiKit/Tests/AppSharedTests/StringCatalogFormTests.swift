//
//  StringCatalogFormTests.swift
//  BatFi
//
//  The committed string catalog must already be in the form Xcode writes.
//

import Foundation
import Testing

import Shared

/// After every build the Xcode IDE merges the strings it finds in code into
/// `Localizable.xcstrings` and rewrites the file in its own form. Anything committed in
/// another form (a hand-added key with its languages out of order, an `extractionState`
/// Xcode disagrees with, different JSON spacing) comes back as an uncommitted diff that
/// gets in the way of every rebase. `scripts/sync-localizable-strings` runs that same merge
/// with Apple's `xcstringstool`; this checks that running it would change nothing.
@Suite struct StringCatalogFormTests {
    @Test func theCatalogIsInTheFormXcodeWrites() async throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../scripts/sync-localizable-strings")
            .standardizedFileURL
        try #require(FileManager.default.fileExists(atPath: script.path), "missing \(script.path)")

        let passed = await Subprocess.run("/usr/bin/python3", arguments: [script.path, "--check"], timeout: .seconds(120))
        #expect(
            passed,
            """
            Localizable.xcstrings is not in the form Xcode writes, so the next build in Xcode will \
            rewrite it. Run scripts/sync-localizable-strings, then review and commit the result \
            (scripts/sync-localizable-strings --check prints the keys that differ).
            """
        )
    }
}
