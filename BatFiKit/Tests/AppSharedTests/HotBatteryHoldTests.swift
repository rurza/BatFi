//
//  HotBatteryHoldTests.swift
//  BatFi
//
//  Unit tests for holding a hot battery where it is by freezing the charge limit.
//

import Foundation
import Shared
import Testing

@testable import AppShared

@Suite struct HotBatteryHoldTests {
    private typealias Hold = HotBatteryHold
    private let threshold = 40.0

    /// One pass, with everything that would start a hold already true, so each test names
    /// only the input it is about.
    private func next(
        frozenAt frozen: Int? = nil,
        isEnabled: Bool = true,
        temperature: Double? = 41,
        chargerConnected: Bool = true,
        batteryLevel: Int = 63,
        backend: ChargeBackend? = .systemChargeLimit
    ) -> Int? {
        Hold.next(
            frozenAt: frozen,
            isEnabled: isEnabled,
            temperature: temperature,
            threshold: threshold,
            chargerConnected: chargerConnected,
            batteryLevel: batteryLevel,
            backend: backend
        )
    }

    // MARK: - Starting a hold

    /// The bug: on Apple's charge limit the setting was hidden and the cutout bypassed, so a
    /// battery at 63% and 41 °C charged on to its 80% limit. Setting the limit to 63 holds it.
    @Test func aHotBatteryOnTheChargerIsHeldWhereItIs() {
        #expect(next() == 63)
    }

    /// Strictly above, the same comparison `HotBatteryProtection` makes, so the two features
    /// cannot disagree about whether 40.0 °C is hot.
    @Test func theThresholdItselfIsNotHot() {
        #expect(next(temperature: 40) == nil)
        #expect(next(temperature: 40.1) == 63)
    }

    /// On battery nothing is charging, and a limit frozen there would be applied on the next
    /// plug-in against a battery that may since have cooled.
    @Test func nothingIsHeldOffTheCharger() {
        #expect(next(chargerConnected: false) == nil)
    }

    @Test func nothingIsHeldWithTheSettingOff() {
        #expect(next(isEnabled: false, temperature: 50) == nil)
    }

    /// No reading is not a hot reading. `HotBatteryProtection.cutoutCannotFire` is what says
    /// so; this rule only declines to invent one.
    @Test func nothingIsHeldWithoutATemperature() {
        #expect(next(temperature: nil) == nil)
    }

    /// The inhibit backends keep the inhibit they have always used, unchanged. The firmware
    /// band would recharge the battery five points below the frozen value while it is still
    /// hot, `.unsupported` has nothing to write, and an unresolved backend is left to the
    /// existing path rather than guessed at.
    @Test func onlyApplesChargeLimitIsHeldByFreezingTheLimit() {
        #expect(next(backend: .systemChargeLimit) == 63)
        #expect(next(backend: .chte) == nil)
        #expect(next(backend: .legacyCH0BC) == nil)
        #expect(next(backend: .firmwareRange) == nil)
        #expect(next(backend: .unsupported) == nil)
        #expect(next(backend: nil) == nil)
    }

    @Test func appliesFollowsTheSameRule() {
        #expect(Hold.applies(to: .systemChargeLimit))
        for backend in ChargeBackend.allCases where backend != .systemChargeLimit {
            #expect(!Hold.applies(to: backend), "\(backend)")
        }
        #expect(!Hold.applies(to: nil))
    }

    // MARK: - The value it freezes at

    /// Frozen from the battery alone, not from the lower of the battery and the limit. The
    /// limit can be a discharge request — "Run on Battery" is a 0% override — and a value
    /// frozen from it would outlive the request: the user stops the discharge, the battery
    /// is still hot, and macOS drains it to 0% on mains power. `requestedLimit` takes the
    /// lower of the two on every pass instead, so the request wins only while it stands.
    @Test func theLevelIsFrozenNotTheLimit() {
        let frozen = next(batteryLevel: 63)
        #expect(frozen == 63)
        // "Run on Battery" while hot: the discharge goes ahead...
        #expect(Hold.requestedLimit(frozenAt: frozen, otherwise: 0) == 0)
        // ...and stopping it hands back the hold, not a 0% limit.
        #expect(Hold.requestedLimit(frozenAt: frozen, otherwise: 80) == 63)
    }

    /// And a battery above the limit is still not held *above* it, which would raise the
    /// limit — the opposite of protecting a hot battery.
    @Test func neverRequestedAboveTheLimitThatWouldOtherwiseApply() {
        let frozen = next(batteryLevel: 85)
        #expect(Hold.requestedLimit(frozenAt: frozen, otherwise: 70) == 70)
    }

    /// `setMCLLimit:` takes 80–100 in steps of five. Rounded *down*, never up: up would let
    /// the battery charge a few more percent while hot, down only lets macOS drain a few on
    /// mains power, which is harmless for a hot battery.
    @Test func atOrAbove80TheLimitIsRoundedDownToAStepOfFive() {
        #expect(next(batteryLevel: 87) == 85)
        #expect(next(batteryLevel: 83) == 80)
        #expect(next(batteryLevel: 99) == 95)
        #expect(next(batteryLevel: 80) == 80)
        #expect(next(batteryLevel: 95) == 95)
        #expect(next(batteryLevel: 100) == 100)
    }

    /// A limit of the user's own that is off the step is theirs, applied as it always is;
    /// the hold rounds only the value it invents.
    @Test func theUsersOwnLimitIsNotRounded() {
        let frozen = next(batteryLevel: 90)
        #expect(frozen == 90)
        #expect(Hold.requestedLimit(frozenAt: frozen, otherwise: 82) == 82)
    }

    /// Below 80 the charge-limit defaults take any value, so it is passed through exactly.
    @Test func below80TheLevelIsPassedThroughExactly() {
        #expect(next(batteryLevel: 79) == 79)
        #expect(next(batteryLevel: 63) == 63)
    }

    /// No floor is invented. Values under 50 have never been measured on hardware, but the
    /// alternative — raising the limit of a hot battery to some floor — charges it.
    @Test func thereIsNoFloor() {
        #expect(next(batteryLevel: 42) == 42)
        #expect(next(batteryLevel: 12) == 12)
    }

    // MARK: - Keeping it

    /// The value never follows the battery. A new limit every pass is a new adoption for
    /// powerd each time — about 45 s of churn per change — and a battery that crept up
    /// while it was being adopted would ratchet the limit up behind it.
    @Test func theFrozenValueIsKeptWhateverTheBatteryDoes() {
        #expect(next(frozenAt: 63, batteryLevel: 66) == 63)
        #expect(next(frozenAt: 63, batteryLevel: 58) == 63)
        #expect(next(frozenAt: 63, temperature: 45, batteryLevel: 70) == 63)
    }

    /// Nor the slider: lowering the limit while the battery is hot is honoured by
    /// `requestedLimit`, and raising it again goes back to the hold, not above it.
    @Test func theSliderMovesTheRequestNotTheHold() {
        #expect(Hold.requestedLimit(frozenAt: 63, otherwise: 55) == 55)
        #expect(Hold.requestedLimit(frozenAt: 63, otherwise: 90) == 63)
    }

    /// Two degrees of hysteresis. Ending the hold at the same line that starts it would
    /// release and re-freeze on every flicker across 40 °C — each one a limit change that
    /// re-arms charging.
    @Test func aHoldOutlastsTheThresholdByTwoDegrees() {
        #expect(next(frozenAt: 63, temperature: 40) == 63)
        #expect(next(frozenAt: 63, temperature: 38.1) == 63)
        #expect(next(frozenAt: 63, temperature: 38) == nil)
        #expect(next(frozenAt: 63, temperature: 30) == nil)
    }

    /// And the band is not a way in: a battery that was never held does not start a hold at
    /// 39 °C.
    @Test func theHysteresisBandDoesNotStartAHold() {
        #expect(next(frozenAt: nil, temperature: 39) == nil)
    }

    // MARK: - Ending it

    @Test func unpluggingEndsTheHold() {
        #expect(next(frozenAt: 63, chargerConnected: false) == nil)
    }

    @Test func turningTheSettingOffEndsTheHold() {
        #expect(next(frozenAt: 63, isEnabled: false) == nil)
    }

    /// A temperature that stops being published cannot show the battery cooling, so holding
    /// on would freeze the limit for as long as the reading stays away.
    @Test func losingTheTemperatureEndsTheHold() {
        #expect(next(frozenAt: 63, temperature: nil) == nil)
    }

    /// After cooling, a still-hot battery freezes at its level *then*, not at the old value.
    @Test func aNewHoldFreezesAfresh() {
        let ended = next(frozenAt: 63, temperature: 37, batteryLevel: 70)
        #expect(ended == nil)
        #expect(next(frozenAt: ended, temperature: 41, batteryLevel: 70) == 70)
    }

    // MARK: - What is requested

    @Test func withoutAHoldTheLimitIsUntouched() {
        #expect(Hold.requestedLimit(frozenAt: nil, otherwise: 80) == 80)
        #expect(Hold.requestedLimit(frozenAt: nil, otherwise: 100) == 100)
    }

    /// Ahead of a charge-to-full hold or a "Charge to 100%" override, which only ever ask for
    /// more — the same precedence the inhibit backends have always given the cutout.
    @Test func aHoldBeatsAHigherRequest() {
        #expect(Hold.requestedLimit(frozenAt: 63, otherwise: 100) == 63)
        #expect(Hold.requestedLimit(frozenAt: 63, otherwise: 80) == 63)
    }

    /// A lower request still wins: the user lowering the slider, or a discharge — "Run on
    /// Battery" is a 0% request — which is fine for a hot battery.
    @Test func aLowerRequestStillWins() {
        #expect(Hold.requestedLimit(frozenAt: 63, otherwise: 55) == 55)
        #expect(Hold.requestedLimit(frozenAt: 63, otherwise: 0) == 0)
    }
}
