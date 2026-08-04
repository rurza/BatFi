//
//  ChargingDiagnosticsTests.swift
//  BatFi
//
//  ChargingDiagnostics crosses the XPC boundary, so every field has to survive an
//  archive/unarchive round trip. A field added to the class but forgotten in either
//  half of the coder decodes as a silent `false` — which for the two availability
//  flags means "this Mac cannot run on battery / has no MagSafe LED" on a machine
//  where both work. Nothing else would fail; the app would just quietly report the
//  wrong thing.
//
//  The other half of this suite pins `systemChargeLimitIsHoldingCharge`, the signal
//  the MagSafe LED reads under Apple's Manual Charge Limit. Both of its halves are
//  load-bearing and a test exists for each.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargingDiagnosticsTests {
    private func diagnostics(
        backend: String = ChargeBackend.chte.rawValue,
        reasons: [String] = [],
        forceDischargeAvailable: Bool? = false,
        magSafeLEDAvailable: Bool? = false,
        firmwareRangeIsArmed: Bool? = nil,
        appliedChargeLimit: Int? = nil,
        chargeLimitWasRaised: Bool = false,
        requestedChargeLimit: Int? = nil
    ) -> ChargingDiagnostics {
        ChargingDiagnostics(
            backend: backend,
            firmwareVersion: "mBoot-18000.161.9",
            notChargingReasons: reasons,
            mcl: MCLStatus(supported: true, batFiHasActiveOverride: false, lastOverrideValue: nil),
            forceDischargeAvailable: forceDischargeAvailable,
            magSafeLEDAvailable: magSafeLEDAvailable,
            firmwareRangeIsArmed: firmwareRangeIsArmed,
            appliedChargeLimit: appliedChargeLimit,
            chargeLimitWasRaised: chargeLimitWasRaised,
            requestedChargeLimit: requestedChargeLimit
        )
    }

    private func roundTrip(_ value: ChargingDiagnostics) throws -> ChargingDiagnostics {
        let data = try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ChargingDiagnostics.self, from: data)
        return try #require(decoded)
    }

    // MARK: - Coding symmetry

    /// Both flags true. A missing `encode` or `decode` line reads back as false, so this
    /// is the direction that catches a half-wired field.
    @Test func availabilityFlagsSurviveTheXPCRoundTripWhenTrue() throws {
        let decoded = try roundTrip(diagnostics(forceDischargeAvailable: true, magSafeLEDAvailable: true))
        #expect(decoded.forceDischargeAvailable == true)
        #expect(decoded.magSafeLEDAvailable == true)
    }

    /// The flags are independent of each other. Firmware that kept CHIE but reports no
    /// ACLC — or the reverse — must not have one answer stand in for the other.
    @Test func availabilityFlagsAreCarriedIndependently() throws {
        let forceOnly = try roundTrip(diagnostics(forceDischargeAvailable: true, magSafeLEDAvailable: false))
        #expect(forceOnly.forceDischargeAvailable == true)
        #expect(forceOnly.magSafeLEDAvailable == false)

        let ledOnly = try roundTrip(diagnostics(forceDischargeAvailable: false, magSafeLEDAvailable: true))
        #expect(ledOnly.forceDischargeAvailable == false)
        #expect(ledOnly.magSafeLEDAvailable == true)
    }

    /// Three-valued, like `firmwareRangeIsArmed`, and for a sharper reason: `false` on
    /// either of these is *acted on* — one of them writes a persisted user setting off —
    /// while nil means only that the helper could not probe. Collapsing them is how a
    /// two-second driver hiccup destroyed a working Mac's green-light setting.
    @Test func anUnaskedProbeRoundTripsAsUnknownRatherThanAsAbsent() throws {
        let decoded = try roundTrip(diagnostics(
            forceDischargeAvailable: nil,
            magSafeLEDAvailable: nil
        ))
        #expect(decoded.forceDischargeAvailable == nil)
        #expect(decoded.magSafeLEDAvailable == nil)
        // And it does not leak into the derived answer either.
        #expect(decoded.magSafeGreenLightAvailable == nil)
    }

    /// The fields that were already there still round trip beside the new ones.
    @Test func existingFieldsStillRoundTrip() throws {
        let decoded = try roundTrip(diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            reasons: [NotChargingReason.systemChargeLimit.rawValue],
            forceDischargeAvailable: true,
            magSafeLEDAvailable: true,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true
        ))
        #expect(decoded.backend == ChargeBackend.systemChargeLimit.rawValue)
        #expect(decoded.firmwareVersion == "mBoot-18000.161.9")
        #expect(decoded.notChargingReasons == [NotChargingReason.systemChargeLimit.rawValue])
        #expect(decoded.appliedChargeLimit == 80)
        #expect(decoded.chargeLimitWasRaised)
        #expect(decoded.mcl?.supported == true)
    }

    /// The requested value rides beside the applied one. Dropped in either half of the
    /// coder it decodes as nil, and the pane then declines to name a reason for the raise
    /// at all — a silent loss of the disclosure this whole field exists to get right.
    @Test func theRequestedLimitSurvivesTheXPCRoundTrip() throws {
        let decoded = try roundTrip(diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            appliedChargeLimit: 90,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 87
        ))
        #expect(decoded.requestedChargeLimit == 87)
        #expect(decoded.appliedChargeLimit == 90)
    }

    /// Absent has to decode as absent rather than as a stored zero — the flag-plus-value
    /// shape, for the same reason `appliedChargeLimit` uses it. Zero is a value a request
    /// can genuinely hold: `dischargeBattery(to:)` accepts any 0...100.
    @Test func anAbsentRequestedLimitRoundTripsAsAbsent() throws {
        let decoded = try roundTrip(diagnostics(requestedChargeLimit: nil))
        #expect(decoded.requestedChargeLimit == nil)
    }

    @Test func aZeroRequestedLimitRoundTripsAsZeroNotAsAbsent() throws {
        let decoded = try roundTrip(diagnostics(appliedChargeLimit: 80, requestedChargeLimit: 0))
        #expect(decoded.requestedChargeLimit == 0)
    }

    // MARK: - firmwareRangeIsArmed

    /// Three-valued on purpose, and the coder has to keep all three apart. "The band is
    /// released" and "this Mac has no band" are different answers to a bug report, and a
    /// plain `decodeBool` would collapse them — which is why the flag-plus-value shape is
    /// here for a `Bool?` and not only for the optional `Int`s.
    @Test func theFirmwareRangeArmedFlagKeepsItsThreeValuesAcrossXPC() throws {
        let armed = try roundTrip(diagnostics(
            backend: ChargeBackend.firmwareRange.rawValue,
            firmwareRangeIsArmed: true
        ))
        #expect(armed.firmwareRangeIsArmed == true)

        let released = try roundTrip(diagnostics(
            backend: ChargeBackend.firmwareRange.rawValue,
            firmwareRangeIsArmed: false
        ))
        #expect(released.firmwareRangeIsArmed == false)

        let notApplicable = try roundTrip(diagnostics(firmwareRangeIsArmed: nil))
        #expect(notApplicable.firmwareRangeIsArmed == nil)
    }

    /// Reported, never branched on — and in particular it is not what tells the app whether
    /// charging is being held back. It was, briefly, through `isChargingEnabled`, and since
    /// the band is armed for as long as a limit is set that made the app read `.inhibit`
    /// while the battery charged. Nothing in `ChargingDiagnostics` reads it.
    @Test func anArmedBandSaysNothingAboutChargingBeingHeldBack() {
        let value = diagnostics(
            backend: ChargeBackend.firmwareRange.rawValue,
            magSafeLEDAvailable: true,
            firmwareRangeIsArmed: true
        )
        #expect(!value.systemChargeLimitIsHoldingCharge)
    }

    // MARK: - magSafeGreenLightAvailable, and what it does not take with it

    /// The narrow question. `.firmwareRange` is the one backend that loses the green light,
    /// because BatFi predicts the firmware's hold from the battery level and the hysteresis
    /// band makes that prediction wrong for most of the time the hold is on.
    @Test func onlyTheFirmwareRangeLosesTheGreenLight() {
        for backend in ChargeBackend.allCases {
            let value = diagnostics(backend: backend.rawValue, magSafeLEDAvailable: true)
            #expect(
                value.magSafeGreenLightAvailable == (backend != .firmwareRange),
                "\(backend.rawValue)"
            )
        }
    }

    /// The ruling this pair exists to enforce: losing the green light must not take the
    /// discharge blink with it. The blink runs off `magSafeLEDAvailable`, which stays true
    /// on this firmware, because it fires on BatFi's own `.forceDischarge` mode rather than
    /// on any knowledge of what the firmware is doing.
    @Test func theDischargeBlinkSurvivesOnFirmwareThatLosesTheGreenLight() {
        let value = diagnostics(
            backend: ChargeBackend.firmwareRange.rawValue,
            forceDischargeAvailable: true,
            magSafeLEDAvailable: true
        )
        #expect(value.magSafeLEDAvailable == true)
        #expect(value.forceDischargeAvailable == true)
        #expect(value.magSafeGreenLightAvailable == false)
    }

    /// No key, no light — on any backend. The narrowing only ever removes.
    @Test func noLEDKeyMeansNoGreenLightOnAnyBackend() {
        for backend in ChargeBackend.allCases {
            let value = diagnostics(backend: backend.rawValue, magSafeLEDAvailable: false)
            #expect(value.magSafeGreenLightAvailable == false, "\(backend.rawValue)")
        }
    }

    /// Fails *open* on a backend string this build does not recognize, unlike
    /// `systemChargeLimitIsHoldingCharge` below. Guessing wrong there invents a claim about
    /// the hardware; guessing wrong here switches off a feature that works, so an older app
    /// talking to a newer helper keeps its light.
    @Test func anUnrecognizedBackendKeepsTheGreenLight() {
        let unknownBackend = "aBackendNoBuildHasEverShipped"
        #expect(ChargeBackend(rawValue: unknownBackend) == nil)
        let value = diagnostics(backend: unknownBackend, magSafeLEDAvailable: true)
        #expect(value.magSafeGreenLightAvailable == true)
    }

    /// Read app-side off a decoded instance, so it has to hold across the boundary.
    @Test func theGreenLightAnswerSurvivesTheXPCRoundTrip() throws {
        let decoded = try roundTrip(diagnostics(
            backend: ChargeBackend.firmwareRange.rawValue,
            magSafeLEDAvailable: true
        ))
        #expect(decoded.magSafeLEDAvailable == true)
        #expect(decoded.magSafeGreenLightAvailable == false)
    }

    // MARK: - systemChargeLimitIsHoldingCharge

    /// The case the MagSafe LED exists to mirror: Apple's limit is the backend, and the
    /// firmware itself says the system charge limit is why charging stopped.
    @Test func reportsHoldingChargeUnderTheSystemLimitWithTheCHNCBitSet() {
        let value = diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            reasons: [NotChargingReason.systemChargeLimit.rawValue]
        )
        #expect(value.systemChargeLimitIsHoldingCharge)
    }

    /// Under `.systemChargeLimit` a limit below 80% is raised to one the mechanism can
    /// express, so BatFi's own mode can read `.inhibit` while the hardware charges on.
    /// Without the CHNC bit nothing is being held, and this must say so.
    @Test func doesNotReportHoldingChargeWithoutTheCHNCBit() {
        let value = diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            reasons: [NotChargingReason.batteryFull.rawValue]
        )
        #expect(!value.systemChargeLimitIsHoldingCharge)
    }

    /// The half that protects every machine anyone can actually test. On an SMC backend
    /// BatFi's own inhibit is the signal, and this one must stay false even when the
    /// firmware happens to raise bit 24 — otherwise it would start driving the LED on
    /// hardware whose behaviour is meant to be untouched.
    @Test func staysSilentUnderTheSMCBackendsEvenWithTheCHNCBitSet() {
        for backend in [ChargeBackend.chte, .legacyCH0BC, .unsupported] {
            let value = diagnostics(
                backend: backend.rawValue,
                reasons: [NotChargingReason.systemChargeLimit.rawValue]
            )
            #expect(!value.systemChargeLimitIsHoldingCharge,
                    "\(backend.rawValue) must not drive the LED from CHNC")
        }
    }

    /// A raw backend string this build does not recognize decodes to no backend at all.
    /// Failing closed keeps an unknown future value from being read as Apple's limit.
    @Test func staysSilentForAnUnrecognizedBackendString() {
        let value = diagnostics(
            backend: "firmwareRange",
            reasons: [NotChargingReason.systemChargeLimit.rawValue]
        )
        #expect(!value.systemChargeLimitIsHoldingCharge)
    }

    /// The property is read app-side off a decoded instance, not off the one the helper
    /// built, so it has to hold across the boundary too.
    @Test func survivesTheXPCRoundTrip() throws {
        let decoded = try roundTrip(diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            reasons: [NotChargingReason.systemChargeLimit.rawValue]
        ))
        #expect(decoded.systemChargeLimitIsHoldingCharge)
    }
}
