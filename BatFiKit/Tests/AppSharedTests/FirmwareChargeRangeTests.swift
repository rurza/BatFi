//
//  FirmwareChargeRangeTests.swift
//  BatFi
//
//  The macOS 27 firmware keys encode ui32 percentages LITTLE-endian, against the
//  normal SMC convention every other ui32 key in this codebase follows.
//

import Foundation
import Testing

@testable import Shared

@Suite struct FirmwareChargeRangeTests {
    /// 50% is 32 00 00 00, not 00 00 00 32.
    @Test func encodesPercentageLittleEndian() {
        let bytes = FirmwareChargeRange.encodePercentage(50)
        #expect(bytes == (0x32, 0x00, 0x00, 0x00))
    }

    @Test func encodesFullChargeLittleEndian() {
        #expect(FirmwareChargeRange.encodePercentage(100) == (0x64, 0x00, 0x00, 0x00))
    }

    @Test func roundTripsEveryValidPercentage() {
        for value in 0 ... 100 {
            #expect(FirmwareChargeRange.decodePercentage(FirmwareChargeRange.encodePercentage(value)) == value)
        }
    }

    /// A big-endian reading of 50% would be 838860800 — the check that catches a
    /// byte-order regression outright.
    @Test func decodeIsNotBigEndian() {
        #expect(FirmwareChargeRange.decodePercentage((0x32, 0x00, 0x00, 0x00)) == 50)
        #expect(FirmwareChargeRange.decodePercentage((0x00, 0x00, 0x00, 0x32)) != 50)
    }

    /// BatFi has a single limit; the firmware wants a band. Five points of
    /// hysteresis matches what Apple's own limit uses.
    @Test func derivesBandFromSingleLimit() {
        let band = FirmwareChargeRange.band(forLimit: 80)
        #expect(band.upper == 80)
        #expect(band.lower == 75)
    }

    /// The lower bound must not go absurdly low for small limits.
    @Test func clampsLowerBound() {
        #expect(FirmwareChargeRange.band(forLimit: 12).lower >= 10)
        #expect(FirmwareChargeRange.band(forLimit: 10).lower >= 10)
    }

    @Test func upperNeverExceedsLimit() {
        for limit in 10 ... 100 {
            #expect(FirmwareChargeRange.band(forLimit: limit).upper == limit)
        }
    }
}
