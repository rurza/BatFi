//
//  ManualDischargeSleepNoticeTests.swift
//  BatFi
//
//  Whether to tell the user that "Run on Battery" will stop this Mac sleeping at all.
//
//  On a backend where macOS drains to the limit itself, a manual discharge is the only thing
//  left that drives the SMC — and it takes the adapter out of the circuit, so the Mac runs on
//  battery. `pmset -a disablesleep 1` is what keeps it awake through a lid close, which is the
//  behaviour a clamshell user needs and the one they cannot guess: without it, closing the lid
//  sleeps the machine mid-discharge.
//
//  Disabling sleep outright is a big enough side effect to say out loud once. Suppressible,
//  because someone who uses this deliberately should not be asked twice.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ManualDischargeSleepNoticeTests {
    @Test func theNoticeIsShownWhereAManualDischargeDisablesSleep() {
        #expect(
            ManualDischargeSleepNotice.shouldShow(
                backendOwnsDischarge: true,
                userSuppressed: false
            )
        )
    }

    /// Asked once. The checkbox is the whole point of it being an alert rather than a
    /// notification.
    @Test func aSuppressedNoticeIsNotShownAgain() {
        #expect(
            ManualDischargeSleepNotice.shouldShow(
                backendOwnsDischarge: true,
                userSuppressed: true
            ) == false
        )
    }

    /// On every other backend BatFi's discharge does not reach for `pmset`, so there is no
    /// system-wide side effect to disclose and the alert would be a lie.
    @Test func noNoticeWhereTheDischargeDoesNotDisableSleep() {
        #expect(
            ManualDischargeSleepNotice.shouldShow(
                backendOwnsDischarge: false,
                userSuppressed: false
            ) == false
        )
    }

    /// Belt and braces: suppression must not resurrect the notice on a backend that never
    /// shows it.
    @Test func suppressionCannotTurnTheNoticeOn() {
        #expect(
            ManualDischargeSleepNotice.shouldShow(
                backendOwnsDischarge: false,
                userSuppressed: true
            ) == false
        )
    }
}
