//
//  HotBatteryProtectionTests.swift
//  BatFi
//
//  The regression this suite exists for: `PowerState.batteryTemperature` became optional,
//  and the hot-battery arm was `if enabled, let temperature, temperature > threshold`. A
//  firmware that renames or drops the temperature property therefore falls out of that
//  condition silently — the setting defaults to **on**, so where BatFi previously wrote no
//  SMC state at all it now manages charging with the cutout bypassed and nothing logged.
//

import Testing

@testable import Shared

@Suite struct HotBatteryProtectionTests {
    private let threshold = Constant.batteryTemperatureWarning

    /// The finding, as a value: enabled plus no reading is its own answer, not "fine".
    @Test func aMissingTemperatureIsNotTreatedAsAColdBattery() {
        #expect(
            HotBatteryProtection.decision(isEnabled: true, temperature: nil, threshold: threshold)
                == .cutoutCannotFire
        )
    }

    /// And it is only reported where the user actually asked for the protection. Saying it
    /// on a Mac with the setting off would be noise about a feature nobody enabled.
    @Test func nothingIsSaidWhenTheProtectionIsSwitchedOff() {
        #expect(
            HotBatteryProtection.decision(isEnabled: false, temperature: nil, threshold: threshold)
                == .notEnabled
        )
        #expect(
            HotBatteryProtection.decision(isEnabled: false, temperature: 99, threshold: threshold)
                == .notEnabled
        )
    }

    @Test func aHotBatteryStillHoldsCharging() {
        #expect(
            HotBatteryProtection.decision(isEnabled: true, temperature: 45, threshold: threshold)
                == .tooHot(temperature: 45)
        )
    }

    /// Strictly greater, unchanged from the original condition — the threshold itself is
    /// not "too hot", and `BatteryInfoView` colours the row at `>=` on purpose.
    @Test func theThresholdItselfIsWithinLimits() {
        #expect(
            HotBatteryProtection.decision(isEnabled: true, temperature: threshold, threshold: threshold)
                == .withinLimits
        )
        #expect(
            HotBatteryProtection.decision(isEnabled: true, temperature: threshold + 0.1, threshold: threshold)
                == .tooHot(temperature: threshold + 0.1)
        )
    }

    @Test func aCoolBatteryChargesOn() {
        #expect(
            HotBatteryProtection.decision(isEnabled: true, temperature: 30.8, threshold: threshold)
                == .withinLimits
        )
    }
}
