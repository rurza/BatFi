//
//  PmsetCustomOutputTests.swift
//  BatFi
//
//  Unit tests for reading one setting per power source out of `pmset -g custom` output.
//

import Foundation
import Testing

@testable import Shared

@Suite struct PmsetCustomOutputTests {
    /// Real, untrimmed `pmset -g custom` output from a Mac15,8 on macOS 27. The two sections
    /// share every key, and several of them differ between the sections (`displaysleep`,
    /// `womp`), which is what a parser that stops at the first match gets wrong.
    private let realOutput = """
    Battery Power:
     Sleep On Power Button 1
     powermode            0
     standby              1
     ttyskeepawake        1
     hibernatemode        3
     powernap             1
     hibernatefile        /var/vm/sleepimage
     displaysleep         5
     womp                 0
     networkoversleep     0
     sleep                1
     lessbright           1
     tcpkeepalive         1
     disksleep            10
    AC Power:
     Sleep On Power Button 1
     powermode            0
     standby              1
     ttyskeepawake        1
     hibernatemode        3
     powernap             1
     hibernatefile        /var/vm/sleepimage
     displaysleep         20
     womp                 1
     networkoversleep     0
     sleep                1
     tcpkeepalive         1
     disksleep            10
    """

    /// A Mac without High Power Mode: same layout, but the setting is the 0/1
    /// `lowpowermode`. This one is set to Only on Battery.
    private let lowPowerModeOnlyOutput = """
    Battery Power:
     Sleep On Power Button 1
     lowpowermode         1
     standby              1
     displaysleep         2
    AC Power:
     Sleep On Power Button 1
     lowpowermode         0
     standby              1
     displaysleep         10
    """

    @Test func readsEachSectionOfARealMac() {
        #expect(PmsetCustomOutput.values(forKey: "displaysleep", in: realOutput) == [.battery: 5, .ac: 20])
        #expect(PmsetCustomOutput.values(forKey: "womp", in: realOutput) == [.battery: 0, .ac: 1])
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: realOutput) == [.battery: 0, .ac: 0])
    }

    @Test func readsAKeyOnlyOneSectionHas() {
        #expect(PmsetCustomOutput.values(forKey: "lessbright", in: realOutput) == [.battery: 1])
    }

    @Test func readsThePowerModeOfARealMac() {
        #expect(
            PmsetCustomOutput.powerModeBySource(in: realOutput)
                == PowerModeBySource(battery: 0, ac: 0, usesPowermodeKey: true)
        )
    }

    @Test func fallsBackToLowPowerModeOnAMacWithoutHighPowerMode() {
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: lowPowerModeOnlyOutput).isEmpty)
        #expect(
            PmsetCustomOutput.powerModeBySource(in: lowPowerModeOnlyOutput)
                == PowerModeBySource(battery: 1, ac: 0, usesPowermodeKey: false)
        )
    }

    /// `powermode` wins as soon as either section has it, even where the other section
    /// only has `lowpowermode`: the two are never mixed into one answer.
    @Test func prefersPowermodeWhenEitherSectionHasIt() {
        let output = """
        Battery Power:
         lowpowermode 1
        AC Power:
         powermode 2
        """
        #expect(
            PmsetCustomOutput.powerModeBySource(in: output)
                == PowerModeBySource(battery: nil, ac: 2, usesPowermodeKey: true)
        )
    }

    /// A desktop, or a laptop whose AC profile is not published: the battery value is still
    /// read and the AC one is absent rather than borrowed from the battery section.
    @Test func leavesTheACValueAbsentWhenThereIsNoACSection() {
        let output = """
        Battery Power:
         powermode            1
         displaysleep         5
        """
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output) == [.battery: 1])
        #expect(
            PmsetCustomOutput.powerModeBySource(in: output)
                == PowerModeBySource(battery: 1, ac: nil, usesPowermodeKey: true)
        )
    }

    /// A Mac on a UPS gets a third section. It is neither of the two profiles BatFi writes,
    /// so its values are ignored wherever it appears — including first.
    @Test func ignoresTheUPSSection() {
        let output = """
        UPS Power:
         powermode            2
        Battery Power:
         powermode            1
        AC Power:
         powermode            0
        UPS Power:
         powermode            2
        """
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output) == [.battery: 1, .ac: 0])
    }

    @Test func findsNothingWhenOnlyTheUPSSectionHasTheKey() {
        let output = """
        UPS Power:
         powermode            2
        """
        #expect(PmsetCustomOutput.powerModeBySource(in: output) == nil)
    }

    /// `pmset -g` output has no per-source sections at all. Feeding it here by mistake must
    /// not produce a battery value.
    @Test func ignoresSettingsOutsideAnyPowerSourceSection() {
        let output = """
        System-wide power settings:
        Currently in use:
         powermode            0
        """
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output).isEmpty)
        #expect(PmsetCustomOutput.powerModeBySource(in: output) == nil)
    }

    @Test func separatesByTabsAsWellAsSpaces() {
        let output = "Battery Power:\t\n\tpowermode\t\t2\nAC Power:\n powermode \t 0\n"
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output) == [.battery: 2, .ac: 0])
    }

    /// `powermode` and `lowpowermode` are different settings. Matching on substrings or
    /// prefixes would read one as the other, or read an unrelated setting that merely
    /// starts with the same letters.
    @Test func matchesWholeKeysOnly() {
        let output = """
        Battery Power:
         lowpowermodefoo      1
         powermodeX           1
         xpowermode           1
        AC Power:
         lowpowermodefoo      1
         powermodeX           1
        """
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output).isEmpty)
        #expect(PmsetCustomOutput.values(forKey: "lowpowermode", in: output).isEmpty)
        #expect(PmsetCustomOutput.powerModeBySource(in: output) == nil)
    }

    /// The key is the setting's name, which starts the line. The same word further along is
    /// part of some other setting's value, and the number after it is not the setting's.
    @Test func matchesTheKeyOnlyAtTheStartOfALine() {
        let output = """
        Battery Power:
         assertedby           powermode 2
        AC Power:
         assertedby           powermode 2
         powermode            0
        """
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output) == [.ac: 0])
    }

    @Test func aLookalikeKeyDoesNotHideTheRealOne() {
        let output = """
        Battery Power:
         powermodeX           2
         powermode            0
        """
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: output) == [.battery: 0])
    }

    @Test func leavesAValueThatIsNotANumberAbsent() {
        #expect(PmsetCustomOutput.values(forKey: "hibernatefile", in: realOutput).isEmpty)
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: "Battery Power:\n powermode").isEmpty)
    }

    @Test func findsNothingInEmptyOutput() {
        #expect(PmsetCustomOutput.values(forKey: "powermode", in: "").isEmpty)
        #expect(PmsetCustomOutput.powerModeBySource(in: "") == nil)
    }
}
