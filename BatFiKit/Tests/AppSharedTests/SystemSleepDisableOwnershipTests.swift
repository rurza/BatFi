//
//  SystemSleepDisableOwnershipTests.swift
//  BatFi
//
//  Unit tests for the pure policy that decides whether BatFi may write the system-wide
//  `pmset disablesleep` flag.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SystemSleepDisableOwnershipTests {
    private typealias Policy = SystemSleepDisableOwnership
    private typealias Decision = SystemSleepDisableOwnership.Decision

    /// The bug this exists to prevent (issue #148). `SleepDisabled` is system-wide and a
    /// user can set it by hand with `sudo pmset -a disablesleep 1`. BatFi's release path
    /// runs on ordinary charging passes, so an unconditional write took the user's flag
    /// down within minutes of them setting it.
    @Test func doesNotClearAFlagItNeverSet() {
        #expect(
            Policy.decide(disable: false, batFiHoldsIt: false, systemAlreadyDisabled: true)
                == Decision(writes: false, batFiHoldsIt: false)
        )
    }

    /// The other half: what BatFi took, BatFi puts back. Nothing else releases it, so a
    /// missed write here leaves a Mac that cannot sleep.
    @Test func clearsTheFlagItSetItself() {
        #expect(
            Policy.decide(disable: false, batFiHoldsIt: true, systemAlreadyDisabled: true)
                == Decision(writes: true, batFiHoldsIt: false)
        )
    }

    @Test func takesTheFlagWhenSleepIsEnabled() {
        #expect(
            Policy.decide(disable: true, batFiHoldsIt: false, systemAlreadyDisabled: false)
                == Decision(writes: true, batFiHoldsIt: true)
        )
    }

    /// Ownership is about who *changed* the flag, not who wants it set. A user who already
    /// has it on gets no write and no claim — so the discharge that follows cannot hand
    /// BatFi a licence to clear it afterwards.
    @Test func doesNotClaimAFlagTheUserHadOnAlready() {
        #expect(
            Policy.decide(disable: true, batFiHoldsIt: false, systemAlreadyDisabled: true)
                == Decision(writes: false, batFiHoldsIt: false)
        )
    }

    /// Re-asserted rather than assumed: a discharge pass that asks again while BatFi
    /// already holds the flag writes again, which is what recovers a flag something else
    /// cleared mid-discharge.
    @Test func reassertsWhileItAlreadyHoldsTheFlag() {
        #expect(
            Policy.decide(disable: true, batFiHoldsIt: true, systemAlreadyDisabled: false)
                == Decision(writes: true, batFiHoldsIt: true)
        )
    }

    /// `nil` is "the live value could not be read" — an old helper, a `pmset` that timed
    /// out. Claiming is the safe way to be wrong: BatFi then cleans up after itself, where
    /// declining to claim would strand a flag nothing releases.
    @Test func claimsTheFlagWhenTheLiveValueCannotBeRead() {
        #expect(
            Policy.decide(disable: true, batFiHoldsIt: false, systemAlreadyDisabled: nil)
                == Decision(writes: true, batFiHoldsIt: true)
        )
    }

    /// Versions before the ownership record kept it in memory only, so one that died or
    /// was updated mid-discharge left a flag up that nothing knew to take down. Without
    /// this the new record starts empty, declines to claim what it finds, and the Mac never
    /// sleeps again — a worse failure than the one being fixed.
    @Test func adoptsAFlagAnEarlierVersionCouldHaveLeftUp() {
        #expect(
            Policy.adoptsFlagLeftByAnEarlierVersion(
                systemAlreadyDisabled: true,
                disableSleepDuringDischarging: true
            )
        )
    }

    /// The case from issue #148 itself, and the reason this is not simply "the flag is up,
    /// take it". With nothing on that could have disabled sleep during a discharge, a flag
    /// that is up was set by somebody else — and adopting it would clear it exactly once,
    /// which is the bug in miniature.
    @Test func leavesAFlagNoEarlierVersionCouldHaveSet() {
        #expect(
            !Policy.adoptsFlagLeftByAnEarlierVersion(
                systemAlreadyDisabled: true,
                disableSleepDuringDischarging: false
            )
        )
    }

    @Test func adoptsNothingWhenSleepIsNotDisabled() {
        #expect(
            !Policy.adoptsFlagLeftByAnEarlierVersion(
                systemAlreadyDisabled: false,
                disableSleepDuringDischarging: true
            )
        )
    }

    /// Unknown is not a licence to claim here, unlike at a fresh take: nothing is being
    /// written, so there is no flag of BatFi's to lose track of — only somebody else's to
    /// wrongly adopt.
    @Test func adoptsNothingWhenTheLiveValueCannotBeRead() {
        #expect(
            !Policy.adoptsFlagLeftByAnEarlierVersion(
                systemAlreadyDisabled: nil,
                disableSleepDuringDischarging: true
            )
        )
    }

    /// A release when nothing is held is the common case — it runs on every ordinary
    /// charging pass — and must stay silent whether or not the live value could be read.
    @Test func staysSilentReleasingWhatItDoesNotHold() {
        #expect(
            Policy.decide(disable: false, batFiHoldsIt: false, systemAlreadyDisabled: nil)
                == Decision(writes: false, batFiHoldsIt: false)
        )
        #expect(
            Policy.decide(disable: false, batFiHoldsIt: false, systemAlreadyDisabled: false)
                == Decision(writes: false, batFiHoldsIt: false)
        )
    }
}
