//
//  DefaultsKeys.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import AppShared
import Defaults
import Foundation

// AutomationRule is a Codable value type in AppShared; Defaults bridges Codable types
// automatically, so a conformance declaration is all that's needed to persist them.
extension AutomationRule: Defaults.Serializable {}

public extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: true)
    static let onboardingIsDone = Key<Bool>("onboardingIsDone", default: false)

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: true)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    static let allowDischargingFullBattery = Key<Bool>("allowDischargingFullBattery", default: false)
    static let disableSleepDuringDischarging = Key<Bool>("disableSleepDuringDischarging", default: false)
    /// Whether the user has ticked "Don't show this again" on the alert that discloses that a
    /// manual discharge disables sleep entirely — lid close included. Only ever reached on a
    /// backend where macOS drains to the limit itself; see `ManualDischargeSleepNotice`.
    static let suppressManualDischargeSleepNotice = Key<Bool>("suppressManualDischargeSleepNotice", default: false)

    // Menu bar
    static let showMenuBarIcon = Key<Bool>("showMenuBarIcon", default: true)
    static let showStaticMenuBarIcon = Key<Bool>("showStaticMenuBarIcon", default: false)
    static let showBatteryPercentageInStatusIcon = Key<Bool>("showBatteryPercentageInStatusIcon", default: false)
    static let monochromeStatusIcon = Key<Bool>("monochromeStatusIcon", default: true)
    static let showChart = Key<Bool>("showChart", default: false)
    static let showPowerDiagram = Key<Bool>("showPowerDiagram", default: true)
    static let showHighEnergyImpactProcesses = Key<Bool>("showHighEnergyImpactProcesses", default: true)
    static let showPercentageOnBatteryIcon = Key<Bool>("showPercentageOnBatteryIcon", default: true)

    static let showBatteryCycleCount = Key<Bool>("showBatteryCycleCount", default: false)
    static let showBatteryHealth = Key<Bool>("showBatteryHealth", default: false)
    static let showBatteryTemperature = Key<Bool>("showBatteryTemperature", default: false)
    static let showPowerSource = Key<Bool>("showPowerSource", default: false)
    static let showElapsedTime = Key<Bool>("showElapsedTime", default: false)
    static let showLastDischarge = Key<Bool>("showLastDischarge", default: false)
    static let showLastFullCharge = Key<Bool>("showLastFullCharge", default: false)
    static let showPowerModeOptions = Key<Bool>("showPowerModeOptions", default: false)

    static let showTimeLeftNextToStatusIcon = Key<Bool>("showTimeLeftNextToStatusIcon", default: false)

    // Advanced
    static let downloadBetaVersion = Key<Bool>("downloadBetaVersion", default: false)
    // Off everywhere, debug builds included: it is opt-in from Settings › Advanced.
    static let showDebugMenu = Key<Bool>("showDebugMenu", default: false)
    static let disableSleep = Key<Bool>("disableSleep", default: false)
    static let showGreenLightMagSafeWhenInhibiting = Key<Bool>("showGreenLightMagSafeWhenInhibiting", default: false)
    static let turnOnInhibitingChargingWhenGoingToSleep = Key<Bool>("turnOnInhibitingChargingWhenGoingToSleep", default: false)
    static let temperatureSwitch = Key<Bool>("temperatureSwitch", default: true)
    static let turnOnSystemChargeLimitingWhenGoingToSleep = Key<Bool>("turnOnSystemChargeLimitingWhenGoingToSleep", default: false)

    // What this Mac's charge mechanism could do the last time the helper was asked.
    //
    // Cached purely so the settings panes know it *synchronously, on their first render*.
    // The controls these gate are hidden where the firmware cannot honour them, and
    // `SettingsWindowController` sizes its window once from `fittingSize` at the moment a
    // pane is installed — before any async fetch can answer. Deciding visibility from the
    // fetch alone would draw the pane at full height, drop the controls a moment later and
    // leave a blank gap the window can never close, on every single visit.
    //
    // Optimistic by default: a Mac that has never been asked shows every control, which is
    // what BatFi has always done. The values are refreshed whenever diagnostics arrive, so
    // a firmware change costs exactly one stale render before it settles.
    static let lastKnownCanPauseCharging = Key<Bool>("lastKnownCanPauseCharging", default: true)
    static let lastKnownForceDischargeAvailable = Key<Bool>("lastKnownForceDischargeAvailable", default: true)

    // The raw `ChargeBackend` this Mac last reported, or nil where it has never answered.
    //
    // Cached for the same reason as the two above — a view cannot wait on an async fetch
    // without visibly correcting itself afterwards — but with one difference that matters:
    // it is written in a single place, the `chargingDiagnostics` closure in
    // `ChargingClient.liveValue`, so every successful fetch anywhere in the app refreshes it
    // and no caller has to remember to. The two keys above are still refreshed per-view in
    // `ChargingView.refreshCapabilityCache()`; moving them here would be an improvement and
    // is deliberately not part of this change.
    //
    // Stored as the raw string rather than the enum so this module needs no dependency on
    // `Shared`. Nil means unresolved, which `ChargeLimitRange.lowestSelectable` answers with
    // the permissive 50% floor — the same answer a Mac that has never been asked deserves.
    static let lastKnownChargeBackend = Key<String?>("lastKnownChargeBackend", default: nil)

    static let highEnergyImpactProcessesThreshold = Key<Int>("highEnergyImpactProcessesThreshold", default: 500)
    static let highEnergyImpactProcessesDuration = Key<TimeInterval>("highEnergyImpactProcessesDuration", default: 180)
    static let highEnergyImpactProcessesCapacity = Key<Int>("highEnergyImpactProcessesCapacity", default: 5)

    static let sendAnalytics = Key<Bool>("sendAnalytics", default: true)

    // notifications
    static let showChargingStausChanged = Key<Bool>("showChargingStausChanged", default: true)
    static let showOptimizedBatteryCharging = Key<Bool>("showOptimizedBatteryCharging", default: true)
    static let blinkMagSafeWhenDischarging = Key<Bool>("blinkMagSafeWhenDischarging", default: false)
    static let showBatteryLowNotification = Key<Bool>("showBatteryLowNotification", default: false)
    static let batteryLowNotificationThreshold = Key<Int>("batteryLowNotificationThreshold", default: 20)
    static let showRemindersToDischargeAndChargeBattery = Key<Bool>("showRemindersToDischargeAndChargeBattery", default: true)

    // feature flags
    static let enableHighEnergyImpactProcesses = Key<Bool>("enableHighEnergyImpactProcesses", default: false)
    static let enablePowerDiagram = Key<Bool>("enablePowerDiagram", default: false)

    // charging reminder
    static let lastChargingReminderDate = Key<Date>("lastChargingReminderDate", default: Date.distantPast)

    // Calendar / automation
    static let automationEnabled = Key<Bool>("automationEnabled", default: false)
    static let automationRules = Key<[AutomationRule]>("automationRules", default: [])
    /// Written by the automation engine: the id of the rule currently driving charging
    /// (empty when none). Read by the settings pane and menu to show an ACTIVE badge.
    static let automationActiveRuleID = Key<String>("automationActiveRuleID", default: "")
}
