//
//  ChargeToFullHoldTests.swift
//  BatFi
//
//  Unit tests for the pure "keep holding 100% until the charger comes out" rule.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeToFullHoldTests {
    private typealias Hold = ChargeToFullHold

    /// The bug, from a customer log of 2026-09-22. "Charge to 100%" armed with the charger
    /// in, a 70% limit on the firmware range backend, "Discharge battery when overcharged"
    /// on. At 11:02:28 the battery reached 100%, the override was retired — and the very
    /// next status pass read 100% against a 70–75% band with discharging allowed and began
    /// force-discharging the 30% the user had just asked for, for twenty minutes.
    ///
    /// Completing the charge is what *starts* the hold: the request stays at 100 until the
    /// charger is unplugged, so the no-override branch sees a battery at its limit and
    /// inhibits instead of draining.
    @Test func completingTheChargeStartsTheHold() {
        #expect(Hold.next(holding: false, event: .chargeToFullCompleted))
    }

    /// The hold ends where the user's own limit becomes relevant again. Until the charger
    /// comes out there is nothing to protect the battery from — it is sitting on mains
    /// power at the level the user asked for.
    @Test func unpluggingTheChargerEndsTheHold() {
        #expect(!Hold.next(holding: true, event: .chargerDisconnected))
    }

    /// A new temp override replaces the intent the hold came from. The hold is the residue
    /// of a request that has been superseded, so it must not outlive it and re-assert 100
    /// once the new override is retired.
    @Test func armingANewOverrideEndsTheHold() {
        #expect(!Hold.next(holding: true, event: .overrideArmed))
    }

    /// Charge management off, or any other disengage: BatFi is handing charging back and
    /// has no limit of its own in force, so it cannot be holding one.
    @Test func handingChargingBackEndsTheHold() {
        #expect(!Hold.next(holding: true, event: .chargingHandedBack))
    }

    /// The completion site is reached once, but the flag is idempotent by construction —
    /// nothing downstream has to care whether this is the first pass that saw it.
    @Test func completingAgainWhileHoldingStaysHolding() {
        #expect(Hold.next(holding: true, event: .chargeToFullCompleted))
    }

    /// Clearing events are harmless when nothing is held. A charger unplugged on an
    /// ordinary pass is not an event this rule has to guard against seeing.
    @Test func clearingEventsWithNoHoldAreNoOps() {
        #expect(!Hold.next(holding: false, event: .chargerDisconnected))
        #expect(!Hold.next(holding: false, event: .overrideArmed))
        #expect(!Hold.next(holding: false, event: .chargingHandedBack))
    }

    /// The hold *is* the requested limit. Nothing suppresses the discharge arm: with 100 in
    /// force the battery is at its limit rather than above it, and the existing no-override
    /// branch inhibits at 100% and charges at 99% on its own.
    @Test func theHoldRequestsAHundred() {
        #expect(Hold.requestedLimit(holding: true, otherwise: 70) == 100)
        #expect(Hold.requestedLimit(holding: true, otherwise: 100) == 100)
    }

    /// Off the hold, the caller's own limit is untouched — the user's configured one, or an
    /// automation rule's.
    @Test func withoutAHoldTheCallersLimitIsUsed() {
        #expect(Hold.requestedLimit(holding: false, otherwise: 70) == 70)
        #expect(Hold.requestedLimit(holding: false, otherwise: 0) == 0)
    }
}
