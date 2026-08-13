//
//  PmsetOutputTests.swift
//  BatFi
//
//  Unit tests for reading a settings value out of `pmset -g` output.
//

import Foundation
import Testing

@testable import Shared

@Suite struct PmsetOutputTests {
    /// Real `pmset -g` output, trimmed. Note the two awkward shapes it contains: a value
    /// followed by a parenthetical, and a key separated from its value by tabs.
    private let sample = """
    System-wide power settings:
     SleepDisabled\t\t0
    Currently in use:
     standby              1
     Sleep On Power Button 1
     hibernatefile        /var/vm/sleepimage
     powernap             1
     disksleep            10
     sleep                1 (sleep prevented by caffeinate, Music, powerd)
     hibernatemode        3
     displaysleep         10
     powermode            0
     womp                 1
    """

    @Test func readsAValueByKey() {
        #expect(PmsetOutput.value(forKey: "powermode", in: sample) == 0)
        #expect(PmsetOutput.value(forKey: "hibernatemode", in: sample) == 3)
        #expect(PmsetOutput.value(forKey: "disksleep", in: sample) == 10)
    }

    /// `lowpowermode` and `powermode` are different settings, and only some Macs publish
    /// the latter. Matching on substrings would conflate them, which is why the shelled-out
    /// version this replaces passed `-w` to `grep`.
    @Test func matchesWholeKeysOnly() {
        let lowOnly = " lowpowermode        1"
        #expect(PmsetOutput.value(forKey: "powermode", in: lowOnly) == nil)
        #expect(PmsetOutput.value(forKey: "lowpowermode", in: lowOnly) == 1)
    }

    /// `sleep` carries a parenthetical listing what is holding it off. Reading the value as
    /// "whatever follows the last space" — which is what the shelled-out version did —
    /// yields "powerd)" here.
    @Test func readsTheValueAfterTheKeyRatherThanTheEndOfTheLine() {
        #expect(PmsetOutput.value(forKey: "sleep", in: sample) == 1)
    }

    @Test func handlesTabSeparatedKeys() {
        #expect(PmsetOutput.value(forKey: "SleepDisabled", in: sample) == 0)
    }

    @Test func returnsNilWhenTheKeyIsAbsent() {
        #expect(PmsetOutput.value(forKey: "powermode", in: "Currently in use:\n standby 1") == nil)
        #expect(PmsetOutput.value(forKey: "powermode", in: "") == nil)
    }

    @Test func returnsNilWhenTheValueIsNotANumber() {
        #expect(PmsetOutput.value(forKey: "hibernatefile", in: sample) == nil)
    }

    @Test func returnsNilWhenTheKeyEndsTheLine() {
        #expect(PmsetOutput.value(forKey: "powermode", in: " powermode") == nil)
    }
}
