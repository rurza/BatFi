//
//  NotChargingReasonTests.swift
//  BatFi
//
//  CHNC is the firmware's own reason for not charging. Bit positions are Asahi's,
//  cross-checked against a live read on a Mac15,8: unplugged reported
//  80 00 00 00 00 00 00 00, which decodes little-endian to bit 7, NO_CHARGER.
//

import Foundation
import Testing

@testable import Shared

@Suite struct NotChargingReasonTests {
    @Test func decodesNoChargerFromLiveReading() {
        let bytes: [UInt8] = [0x80, 0, 0, 0, 0, 0, 0, 0]
        let reasons = NotChargingReason.decode(bytes)
        #expect(reasons.contains(.noCharger))
        #expect(!reasons.contains(.batteryFull))
    }

    @Test func decodesBatteryFull() {
        let bytes: [UInt8] = [0x01, 0, 0, 0, 0, 0, 0, 0]
        #expect(NotChargingReason.decode(bytes).contains(.batteryFull))
    }

    /// Bit 24 lives in the fourth byte little-endian.
    @Test func decodesSystemChargeLimit() {
        let bytes: [UInt8] = [0, 0, 0, 0x01, 0, 0, 0, 0]
        #expect(NotChargingReason.decode(bytes).contains(.systemChargeLimit))
    }

    /// Bit 54 lives in the seventh byte little-endian.
    @Test func decodesForceDischargeCH0I() {
        let bytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0x40, 0]
        #expect(NotChargingReason.decode(bytes).contains(.adapterDisabledCH0I))
    }

    @Test func decodesNothingWhenClear() {
        #expect(NotChargingReason.decode([UInt8](repeating: 0, count: 8)).isEmpty)
    }

    @Test func ignoresShortBuffers() {
        #expect(NotChargingReason.decode([0x80]).isEmpty)
    }
}

/// Which of the firmware's reasons mean *something is holding charge back* — the question
/// `ChargeHoldDrift` asks before deciding a battery sitting above its limit is a fault.
///
/// The distinction is the whole check. A full battery reports a reason too, and reading
/// "the firmware gave a reason" as "the limit is working" would make the fault invisible
/// in exactly the state a user is in when they write in: 100%, nothing charging, no limit
/// left holding anything.
@Suite struct NotChargingReasonHoldTests {
    @Test func aSystemChargeLimitIsAHold() {
        #expect(NotChargingReason.systemChargeLimit.holdsChargeBack)
    }

    @Test func batFisOwnInhibitsAreHolds() {
        #expect(NotChargingReason.inhibitedCH0C.holdsChargeBack)
        #expect(NotChargingReason.inhibitedCH0BOrCH0K.holdsChargeBack)
    }

    /// Force discharge stops charging too, and BatFi is the one doing it. Counting it as a
    /// hold is what keeps "Run on Battery" above the limit from being reported as a fault.
    @Test func aDisabledAdapterIsAHold() {
        #expect(NotChargingReason.adapterDisabledCH0I.holdsChargeBack)
        #expect(NotChargingReason.adapterDisabledCH0J.holdsChargeBack)
    }

    /// The one that matters most. A battery at 100% with no limit in force reports exactly
    /// this and nothing else.
    @Test func aFullBatteryIsNotAHold() {
        #expect(NotChargingReason.batteryFull.holdsChargeBack == false)
    }

    @Test func anAbsentChargerIsNotAHold() {
        #expect(NotChargingReason.noCharger.holdsChargeBack == false)
    }

    /// Transient, and not a limit. Letting it read as a hold would mask a real fault for as
    /// long as battery management stayed busy; the drift clock is what absorbs the blips.
    @Test func busyBatteryManagementIsNotAHold() {
        #expect(NotChargingReason.batteryManagementBusy.holdsChargeBack == false)
    }
}
