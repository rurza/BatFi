//
//  ChargeBackendResolverTests.swift
//  BatFi
//
//  Mechanism selection must follow the firmware's own key table, never the macOS
//  version. These cases encode the three firmware generations plus the traps that
//  a naive "does the key exist?" probe walks into.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargeBackendResolverTests {
    private func cap(_ code: String, _ type: String, _ size: UInt32,
                     readable: Bool = true, writable: Bool = true) -> SMCKeyCapability {
        SMCKeyCapability(code: code, type: type, size: size, isReadable: readable, isWritable: writable)
    }

    private func table(_ caps: [SMCKeyCapability]) -> [String: SMCKeyCapability] {
        Dictionary(uniqueKeysWithValues: caps.map { ($0.code, $0) })
    }

    /// Tahoe-era firmware: CHTE present as a writable ui32.
    @Test func selectsCHTEWhenPresentAndWritable() {
        let caps = table([cap("CHTE", "ui32", 4)])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// Legacy firmware: the CH0B/CH0C pair.
    @Test func selectsLegacyWhenBothLegacyKeysPresent() {
        let caps = table([cap("CH0B", "ui8 ", 1), cap("CH0C", "ui8 ", 1)])
        #expect(ChargeBackendResolver.resolve(caps) == .legacyCH0BC)
    }

    /// CHTE outranks the legacy pair when a firmware exposes both.
    @Test func chteOutranksLegacy() {
        let caps = table([cap("CHTE", "ui32", 4), cap("CH0B", "ui8 ", 1), cap("CH0C", "ui8 ", 1)])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// Only one half of the legacy pair is not a usable mechanism.
    @Test func legacyRequiresBothKeys() {
        #expect(ChargeBackendResolver.resolve(table([cap("CH0B", "ui8 ", 1)])) == .unsupported)
        #expect(ChargeBackendResolver.resolve(table([cap("CH0C", "ui8 ", 1)])) == .unsupported)
    }

    /// Wrong size must not be accepted even when the name matches.
    @Test func rejectsCHTEWithWrongSize() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 2)])) == .unsupported)
    }

    /// Wrong type must not be accepted even when name and size match.
    @Test func rejectsCHTEWithWrongType() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "hex_", 4)])) == .unsupported)
    }

    /// A read-only key cannot drive charging.
    @Test func rejectsNonWritableCHTE() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 4, writable: false)])) == .unsupported)
    }

    /// A key the firmware reports but will not let us read cannot drive charging.
    @Test func rejectsNonReadableCHTE() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 4, readable: false)])) == .unsupported)
    }

    /// Zero-size placeholder keys are reported by some firmware and can be neither
    /// read nor written. They must not select a mechanism.
    @Test func rejectsZeroSizePlaceholder() {
        #expect(ChargeBackendResolver.resolve(table([cap("CHTE", "ui32", 0)])) == .unsupported)
    }

    @Test func emptyTableIsUnsupported() {
        #expect(ChargeBackendResolver.resolve([:]) == .unsupported)
    }

    /// Real capability table measured on a Mac15,8 / M3 Max, firmware mBoot-18000.161.9.
    /// Note bfD0 exists there as hex_/2 — an existence-only probe would false-positive
    /// on the macOS 27 mechanism. This must still resolve to .chte.
    @Test func realTahoeFirmwareTableResolvesToCHTE() {
        let caps = table([
            cap("CHTE", "ui32", 4),
            cap("CHIE", "hex_", 1),
            cap("ACLC", "ui8 ", 1),
            cap("bfD0", "hex_", 2, writable: false),
        ])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// The decoy that makes name-only probing unsafe: bfD0 exists on Tahoe-era
    /// firmware as a read-only hex_/2 key with unrelated meaning, while the macOS 27
    /// mechanism needs it as a writable ui32/4. Matching on the name alone would
    /// select the wrong backend on hardware that cannot support it.
    @Test func measuredTahoeBFD0DoesNotMatchTheMacOS27Shape() {
        let measured = cap("bfD0", "hex_", 2, writable: false)
        #expect(!measured.matches(type: "ui32", size: 4, writable: true))
        // ...and it is not merely the writability that saves us:
        #expect(!measured.matches(type: "ui32", size: 4, writable: false))
        #expect(!measured.matches(type: "hex_", size: 4, writable: false))
    }

    /// Apple's limit is the fallback of last resort: only the SMC backends can
    /// express a limit below 80%, so they must outrank it.
    @Test func smcBackendsOutrankSystemChargeLimit() {
        let chte = table([cap("CHTE", "ui32", 4)])
        #expect(ChargeBackendResolver.resolve(chte, systemChargeLimitSupported: true) == .chte)

        let legacy = table([cap("CH0B", "ui8 ", 1), cap("CH0C", "ui8 ", 1)])
        #expect(ChargeBackendResolver.resolve(legacy, systemChargeLimitSupported: true) == .legacyCH0BC)
    }

    /// The macOS 27 case: no usable SMC key, but Apple's limit is available.
    @Test func fallsBackToSystemChargeLimitWhenNoSMCMechanism() {
        #expect(ChargeBackendResolver.resolve([:], systemChargeLimitSupported: true) == .systemChargeLimit)
    }

    @Test func unsupportedWhenNeitherSMCNorSystemLimit() {
        #expect(ChargeBackendResolver.resolve([:], systemChargeLimitSupported: false) == .unsupported)
    }

    /// A zero-size CHTE placeholder must not beat an available system limit.
    @Test func placeholderKeyDoesNotBeatSystemChargeLimit() {
        let caps = table([cap("CHTE", "ui32", 0)])
        #expect(ChargeBackendResolver.resolve(caps, systemChargeLimitSupported: true) == .systemChargeLimit)
    }

    @Test func onlySMCBackendsHonourLimitsBelow80() {
        #expect(ChargeBackend.chte.honoursLimitsBelow80)
        #expect(ChargeBackend.legacyCH0BC.honoursLimitsBelow80)
        #expect(!ChargeBackend.systemChargeLimit.honoursLimitsBelow80)
        #expect(!ChargeBackend.unsupported.honoursLimitsBelow80)
    }

    /// The single decision behind MCL ownership, pinned as behaviour rather than as a
    /// mirror of anything. `SMCService.reconcileMCLOwnership` branches on this property to
    /// choose between writing an override and clearing one, and
    /// `SystemLimitSnapshot.readIsTrustworthy` reads it to decide whether a limit read
    /// could be BatFi's own write. So these four answers *are* both behaviours: making
    /// `.systemChargeLimit` true here would both start BatFi holding an override on macOS 27
    /// firmware and start it trusting a read that could be that override — which is how the
    /// user's saved limit gets overwritten with BatFi's number.
    @Test func onlySMCBackendsWriteAnMCLOverride() {
        #expect(ChargeBackend.chte.writesMCLOverride)
        #expect(ChargeBackend.legacyCH0BC.writesMCLOverride)
        #expect(!ChargeBackend.systemChargeLimit.writesMCLOverride)
        #expect(!ChargeBackend.unsupported.writesMCLOverride)
    }

    private var goldenGateTable: [String: SMCKeyCapability] {
        table([cap("bfF0", "ui8 ", 1), cap("bfD0", "ui32", 4), cap("bfE0", "ui32", 4)])
    }

    @Test func selectsFirmwareRangeWhenAllThreeKeysPresent() {
        #expect(ChargeBackendResolver.resolve(goldenGateTable) == .firmwareRange)
    }

    /// Ranked first on purpose: an old macOS can be running new firmware, so the
    /// presence of the newer mechanism must win over anything older.
    @Test func firmwareRangeOutranksCHTE() {
        var caps = goldenGateTable
        caps["CHTE"] = cap("CHTE", "ui32", 4)
        #expect(ChargeBackendResolver.resolve(caps) == .firmwareRange)
    }

    /// All three keys are required — a partial set is not a usable mechanism.
    @Test func firmwareRangeRequiresAllThreeKeys() {
        for missing in ["bfF0", "bfD0", "bfE0"] {
            var caps = goldenGateTable
            caps.removeValue(forKey: missing)
            #expect(ChargeBackendResolver.resolve(caps) == .unsupported,
                    "removing \(missing) should not leave a usable firmware range backend")
        }
    }

    /// The decoy in its natural habitat: Tahoe-era firmware has bfD0 as a read-only
    /// hex_/2 key and no bfE0 or bfF0 at all. It must resolve to CHTE, not to the
    /// macOS 27 mechanism.
    @Test func tahoeFirmwareWithDecoyBFD0StillSelectsCHTE() {
        let caps = table([
            cap("CHTE", "ui32", 4),
            cap("bfD0", "hex_", 2, writable: false),
        ])
        #expect(ChargeBackendResolver.resolve(caps) == .chte)
    }

    /// Beta 4 moved the key set again. A firmware exposing bfF0 at the wrong shape
    /// must not select this backend — it should fall through, with no version check.
    @Test func rejectsFirmwareRangeWhenBFF0HasWrongShape() {
        var caps = goldenGateTable
        caps["bfF0"] = cap("bfF0", "ui32", 4)
        #expect(ChargeBackendResolver.resolve(caps) == .unsupported)
    }

    @Test func firmwareRangeHonoursLimitsBelow80() {
        #expect(ChargeBackend.firmwareRange.honoursLimitsBelow80)
    }

    // MARK: - What firmware-owned charging costs the user

    /// Honouring a limit and being able to pause on demand are different capabilities, and
    /// `.firmwareRange` is the case that proves it: it applies the user's own value exactly,
    /// below 80% included, and still cannot stop charging at 43% because the battery is
    /// hot. A band has no "stop now" in it.
    ///
    /// Pinned as behaviour, not as a mirror: `ChargingManager` skips the sleep hook where
    /// this is false and `ChargeControlFacts.disclosures` tells the user why, so flipping
    /// an answer here changes both at once.
    @Test func onlyTheInhibitBackendsCanPauseChargingOnDemand() {
        #expect(ChargeBackend.chte.canPauseChargingOnDemand)
        #expect(ChargeBackend.legacyCH0BC.canPauseChargingOnDemand)
        #expect(!ChargeBackend.firmwareRange.canPauseChargingOnDemand)
        #expect(!ChargeBackend.systemChargeLimit.canPauseChargingOnDemand)
        #expect(!ChargeBackend.unsupported.canPauseChargingOnDemand)
    }

    /// The two properties are independent, and this is the pair that shows it: one backend
    /// honours sub-80% limits and cannot pause, the other pauses and cannot honour them.
    /// Collapsing either into the other would mislabel one of these Macs.
    @Test func honouringLimitsAndPausingAreIndependent() {
        #expect(ChargeBackend.firmwareRange.honoursLimitsBelow80)
        #expect(!ChargeBackend.firmwareRange.canPauseChargingOnDemand)
        #expect(!ChargeBackend.systemChargeLimit.honoursLimitsBelow80)
        #expect(ChargeBackend.chte.canPauseChargingOnDemand)
    }

    /// The MagSafe LED goes on exactly one backend, and not because the key went with it.
    ///
    /// `.systemChargeLimit` keeps it: the firmware attributes the hold itself in `CHNC`
    /// bit 24, so BatFi still knows what the light would mean. `.unsupported` keeps it:
    /// nothing holds charge back there, so the green light never fires, but force
    /// discharge can still work and its blink is driven by BatFi's own mode. Only
    /// `.firmwareRange` loses it, and only because the fact the LED displays is missing.
    @Test func onlyTheFirmwareRangeLosesTheMagSafeLED() {
        #expect(!ChargeBackend.firmwareRange.canMirrorChargingStateOnMagSafeLED)
        #expect(ChargeBackend.chte.canMirrorChargingStateOnMagSafeLED)
        #expect(ChargeBackend.legacyCH0BC.canMirrorChargingStateOnMagSafeLED)
        #expect(ChargeBackend.systemChargeLimit.canMirrorChargingStateOnMagSafeLED)
        #expect(ChargeBackend.unsupported.canMirrorChargingStateOnMagSafeLED)
    }
}
