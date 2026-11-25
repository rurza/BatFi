//
//  PreservedDefaultsTests.swift
//  BatFi
//
//  "Reset settings" empties UserDefaults, and some of what is in there is not a setting but
//  a record of system state BatFi changed and must undo. These cover the snapshot that
//  carries those records across the reset, against a throwaway suite rather than
//  `UserDefaults.standard`.
//

import Foundation
import Testing

@testable import AppShared

@Suite final class PreservedDefaultsTests {
    private let suiteName = "PreservedDefaultsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// What `resetSettings()` does, in order: snapshot, empty the suite, restore.
    private func reset(preserving keys: [String]) {
        let preserved = PreservedDefaults(keys: keys, domainName: suiteName, in: defaults)
        removeAll()
        preserved.restore(into: defaults)
    }

    /// The Defaults package's `UserDefaults.removeAll()`, which is what the live reset calls.
    /// Repeated here to exercise the reset without touching the app's defaults.
    private func removeAll() {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }

    private var stored: [String: Any] {
        defaults.persistentDomain(forName: suiteName) ?? [:]
    }

    @Test func aPreservedKeySurvivesWithItsValue() {
        defaults.set(true, forKey: "record")
        defaults.set(#"[{"pid":42}]"#, forKey: "ledger")

        reset(preserving: ["record", "ledger"])

        #expect(stored["record"] as? Bool == true)
        #expect(stored["ledger"] as? String == #"[{"pid":42}]"#)
    }

    @Test func aKeyThatIsNotPreservedIsRemoved() {
        defaults.set(true, forKey: "record")
        defaults.set(42, forKey: "chargeLimit")

        reset(preserving: ["record"])

        #expect(stored["chargeLimit"] == nil)
        #expect(defaults.object(forKey: "chargeLimit") == nil)
    }

    /// The Defaults package registers every key's default value, so a plain read of a key
    /// that was never written still answers. Writing that answer back would turn "never set"
    /// into a stored value; the registration here is what makes the test see the difference.
    @Test func aPreservedKeyThatWasNeverSetStaysAbsent() {
        defaults.register(defaults: ["record": false])
        defaults.set(42, forKey: "chargeLimit")

        reset(preserving: ["record"])

        #expect(stored["record"] == nil)
        #expect(stored.isEmpty)
    }
}
