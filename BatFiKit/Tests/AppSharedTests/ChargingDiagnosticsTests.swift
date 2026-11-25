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

    /// The narrow question. Every backend keeps the green light where the LED key is there —
    /// `.firmwareRange` included, now that BatFi reports the band's hold
    /// (`FirmwareRangeHold`) rather than calling the drift `.charging`.
    @Test func everyBackendKeepsTheGreenLight() {
        for backend in ChargeBackend.allCases {
            let value = diagnostics(backend: backend.rawValue, magSafeLEDAvailable: true)
            #expect(value.magSafeGreenLightAvailable == true, "\(backend.rawValue)")
        }
    }

    /// The firmware range, which used to lose the green light, has both MagSafe indicators.
    @Test func theFirmwareRangeHasTheGreenLightAndTheDischargeBlink() {
        let value = diagnostics(
            backend: ChargeBackend.firmwareRange.rawValue,
            forceDischargeAvailable: true,
            magSafeLEDAvailable: true
        )
        #expect(value.magSafeLEDAvailable == true)
        #expect(value.forceDischargeAvailable == true)
        #expect(value.magSafeGreenLightAvailable == true)
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
            magSafeLEDAvailable: false
        ))
        #expect(decoded.magSafeLEDAvailable == false)
        #expect(decoded.magSafeGreenLightAvailable == false)
    }

    // MARK: - magSafeGreenLightIsSystemDriven

    /// Only Apple's own limit on macOS 27 and later drives the light itself: powerd sets
    /// `ACLC` while the system charge limit holds there, so the setting is hidden rather
    /// than offered as a choice that changes nothing.
    @Test func onlyTheSystemChargeLimitOnMacOS27DrivesTheGreenLightItself() {
        for backend in ChargeBackend.allCases {
            let value = diagnostics(backend: backend.rawValue, magSafeLEDAvailable: true)
            #expect(
                value.magSafeGreenLightIsSystemDriven(osMajorVersion: 27) == (backend == .systemChargeLimit),
                "\(backend.rawValue)"
            )
        }
    }

    /// MPX-40. macOS 26 on firmware a macOS 27 install left behind resolves to the same
    /// backend, and leaves the LED amber while its limit holds — so the light is BatFi's.
    @Test func theSystemChargeLimitOnMacOS26LeavesTheGreenLightToBatFi() {
        for backend in ChargeBackend.allCases {
            let value = diagnostics(backend: backend.rawValue, magSafeLEDAvailable: true)
            #expect(value.magSafeGreenLightIsSystemDriven(osMajorVersion: 26) == false, "\(backend.rawValue)")
        }
    }

    /// System-driven is **not** unavailable, and the pair must not be confused: under
    /// `.systemChargeLimit` the light works, which is the whole reason the switch is hidden
    /// on macOS 27 rather than turned off.
    @Test func aSystemDrivenGreenLightIsStillAvailable() {
        let value = diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            magSafeLEDAvailable: true
        )
        #expect(value.magSafeGreenLightIsSystemDriven(osMajorVersion: 27) == true)
        #expect(value.magSafeGreenLightAvailable == true)
    }

    /// Nil on a backend this build does not know, so an older app talking to a newer helper
    /// renders the ordinary editable control rather than asserting macOS owns the light.
    @Test func anUnrecognizedBackendMakesNoClaimAboutWhoDrivesTheLight() {
        let unknownBackend = "aBackendNoBuildHasEverShipped"
        #expect(ChargeBackend(rawValue: unknownBackend) == nil)
        let value = diagnostics(backend: unknownBackend, magSafeLEDAvailable: true)
        #expect(value.magSafeGreenLightIsSystemDriven(osMajorVersion: 26) == nil)
        #expect(value.magSafeGreenLightIsSystemDriven(osMajorVersion: 27) == nil)
    }

    /// Read app-side off a decoded instance, like every other answer the settings pane uses.
    @Test func theSystemDrivenAnswerSurvivesTheXPCRoundTrip() throws {
        let decoded = try roundTrip(diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            magSafeLEDAvailable: true
        ))
        #expect(decoded.magSafeGreenLightIsSystemDriven(osMajorVersion: 27) == true)
        #expect(decoded.magSafeGreenLightIsSystemDriven(osMajorVersion: 26) == false)
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

    // MARK: - Other charge-control tools

    /// Detected app-side and attached after the XPC fetch: the helper runs as root and
    /// cannot see the user's home, where the battery CLI's LaunchAgent lives.
    @Test func theTextListsEachDetectedToolWithEveryFootprintThatMatched() {
        let text = diagnostics().withOtherChargeTools([
            DetectedChargeTool(tool: .batteryCLI, matchedFootprints: [.homeRelativePath("Library/LaunchAgents/battery.plist"), .path("/usr/local/bin/battery")]),
            DetectedChargeTool(tool: .alDente, matchedFootprint: .bundleID("com.apphousekitchen.aldente-pro")),
        ]).description
        #expect(text.contains(
            "otherChargeTools: battery CLI (~/Library/LaunchAgents/battery.plist, /usr/local/bin/battery), AlDente (app com.apphousekitchen.aldente-pro)"
        ))
    }

    @Test func theTextSaysNoneOnACleanMac() {
        #expect(diagnostics().withOtherChargeTools([]).description.contains("otherChargeTools: none"))
    }

    /// Not scanned yet is not the same report as scanned and found nothing.
    @Test func theTextSaysUnknownBeforeAnyScan() {
        #expect(diagnostics().description.contains("otherChargeTools: —"))
    }

    @Test func attachingToolsKeepsEveryOtherField() {
        let original = diagnostics(
            backend: ChargeBackend.systemChargeLimit.rawValue,
            reasons: [NotChargingReason.systemChargeLimit.rawValue],
            forceDischargeAvailable: true,
            magSafeLEDAvailable: nil,
            firmwareRangeIsArmed: true,
            appliedChargeLimit: 80,
            chargeLimitWasRaised: true,
            requestedChargeLimit: 72
        )
        let tools = [DetectedChargeTool(tool: .bclm, matchedFootprint: .path("/usr/local/bin/bclm"))]
        let attached = original.withOtherChargeTools(tools)
        #expect(attached.otherChargeTools == tools)
        #expect(attached.backend == original.backend)
        #expect(attached.firmwareVersion == original.firmwareVersion)
        #expect(attached.notChargingReasons == original.notChargingReasons)
        #expect(attached.mcl == original.mcl)
        #expect(attached.forceDischargeAvailable == original.forceDischargeAvailable)
        #expect(attached.magSafeLEDAvailable == original.magSafeLEDAvailable)
        #expect(attached.firmwareRangeIsArmed == original.firmwareRangeIsArmed)
        #expect(attached.appliedChargeLimit == original.appliedChargeLimit)
        #expect(attached.chargeLimitWasRaised == original.chargeLimitWasRaised)
        #expect(attached.requestedChargeLimit == original.requestedChargeLimit)
    }
}
