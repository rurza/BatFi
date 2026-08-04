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

    /// Mirrors the arms of `SMCService.reconcileMCLOwnership`, which is the only place an
    /// MCL override is written: its SMC arm writes one, its `.systemChargeLimit` /
    /// `.unsupported` arm clears instead. Pinned here because
    /// `SystemLimitSnapshot.readIsTrustworthy` reads this to decide whether a limit read
    /// could be BatFi's own write — flip an answer without flipping that switch and BatFi
    /// records its own number as the user's saved limit.
    @Test func onlySMCBackendsWriteAnMCLOverride() {
        #expect(ChargeBackend.chte.writesMCLOverride)
        #expect(ChargeBackend.legacyCH0BC.writesMCLOverride)
        #expect(!ChargeBackend.systemChargeLimit.writesMCLOverride)
        #expect(!ChargeBackend.unsupported.writesMCLOverride)
    }
}
