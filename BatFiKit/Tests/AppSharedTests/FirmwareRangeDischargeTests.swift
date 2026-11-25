//
//  FirmwareRangeDischargeTests.swift
//  BatFi
//
//  "Run on Battery" is an override at 0%. Under `.firmwareRange` that 0 went to the helper
//  as the band's limit, which disarmed the band for the whole discharge and re-armed it from
//  scratch when the discharge ended — and the firmware then charged a battery that sat inside
//  the sailing band. The discharge is BatFi's own (`CHIE`) and needs nothing from the band, so
//  the pass asks for what would be in force without the override.
//

import Foundation
import Testing

@testable import AppShared
import Shared

@Suite struct FirmwareRangeDischargeTests {
    private let runOnBattery = UserTempChargingMode(limit: 0)

    @Test func runOnBatteryLeavesTheBandToTheLimitWithoutIt() {
        #expect(FirmwareRangeDischarge.overrideForLimit(runOnBattery, backend: .firmwareRange) == nil)
    }

    /// Any override the band cannot hold — a Shortcuts limit of 5% as much as 0%.
    @Test func everyOverrideTheBandCannotHoldIsLeftOut() {
        for limit in 0 ... FirmwareChargeRange.minimumLowerBound {
            #expect(FirmwareRangeDischarge.overrideForLimit(.init(limit: limit), backend: .firmwareRange) == nil, "\(limit)")
        }
    }

    /// A temporary limit the band can hold is the band's limit, as before: a Shortcuts 60%
    /// over an 80% battery discharges to 60 and the firmware then holds 60.
    @Test func anOverrideTheBandCanHoldIsKept() {
        for limit in [FirmwareChargeRange.lowestHoldableLimit, 50, 60, 80, 100] {
            let override = UserTempChargingMode(limit: limit)
            #expect(FirmwareRangeDischarge.overrideForLimit(override, backend: .firmwareRange) == override, "\(limit)")
        }
    }

    /// Every other backend gets the override exactly as today — 0 included: under Apple's
    /// limit and the inhibit backends 0 is a request those paths already handle.
    @Test func otherBackendsKeepTheOverride() {
        for backend in ChargeBackend.allCases where backend != .firmwareRange {
            #expect(FirmwareRangeDischarge.overrideForLimit(runOnBattery, backend: backend) == runOnBattery, "\(backend.rawValue)")
        }
        #expect(FirmwareRangeDischarge.overrideForLimit(runOnBattery, backend: nil) == runOnBattery)
    }

    @Test func noOverrideIsNoOverride() {
        for backend in ChargeBackend.allCases {
            #expect(FirmwareRangeDischarge.overrideForLimit(nil, backend: backend) == nil)
        }
    }
}
