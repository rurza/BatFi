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
