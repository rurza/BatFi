//
//  DefaultsKeys.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import AppShared
import Defaults
import Foundation
import Shared

// AutomationRule is a Codable value type in AppShared; Defaults bridges Codable types
// automatically, so a conformance declaration is all that's needed to persist them.
extension AutomationRule: Defaults.Serializable {}
// Likewise, from Shared.
extension AutoLowPowerModeRecord: Defaults.Serializable {}
extension ThrottleLedgerEntry: Defaults.Serializable {}
// Stored as its raw string rather than as JSON, so a dictionary of modes is a plain plist
// dictionary of strings. A mode this version does not know drops that one app, not the set.
extension SlowDownMode: Defaults.Serializable, Defaults.PreferRawRepresentable {}

public extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: true)
    static let onboardingIsDone = Key<Bool>("onboardingIsDone", default: false)

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: true)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    /// Whether sailing is on: hold at the limit and charge again only below the resume level.
    static let sailingEnabled = Key<Bool>("sailingEnabled", default: false)
    /// The resume level the person chose. Nil until they first choose one; read it through
    /// `SailingRange.resolvedResumeLevel(limit:stored:)`.
    static let sailingResumeLevel = Key<Int?>("sailingResumeLevel", default: nil)
    static let allowDischargingFullBattery = Key<Bool>("allowDischargingFullBattery", default: false)
    static let disableSleepDuringDischarging = Key<Bool>("disableSleepDuringDischarging", default: false)
    /// Whether the user has ticked "Don't show this again" on the alert that discloses that a
    /// manual discharge disables sleep entirely — lid close included. Only ever reached on a
    /// backend where macOS drains to the limit itself; see `ManualDischargeSleepNotice`.
    static let suppressManualDischargeSleepNotice = Key<Bool>("suppressManualDischargeSleepNotice", default: false)
    /// Whether the system-wide `pmset disablesleep` flag currently up is one **BatFi** put
    /// there. Not a setting — nothing in the UI reads or writes it.
    ///
    /// `SleepDisabled` is global, persistent and settable by hand, and it carries no record
    /// of who set it, so this is that record. It decides whether BatFi is allowed to take
    /// the flag back down; see `SystemSleepDisableOwnership`. Persisted rather than held in
    /// memory because the flag outlives the process: a BatFi that crashed mid-discharge
    /// would otherwise leave a Mac that never sleeps again, with nothing left that knows to
    /// release it.
    static let systemSleepDisabledByBatFi = Key<Bool>("systemSleepDisabledByBatFi", default: false)
    /// Whether the one-off look for a sleep disable left up by a version that predates the
    /// record above has been made. Also not a setting.
    static let didCheckForSleepDisableLeftByAnEarlierVersion = Key<Bool>(
        "didCheckForSleepDisableLeftByAnEarlierVersion",
        default: false
    )

    // Automatic Low Power Mode
    static let autoLowPowerModeEnabled = Key<Bool>("autoLowPowerModeEnabled", default: false)
    /// The charge, in percent, at or below which BatFi turns Low Power Mode on for the
    /// battery. Settings offers 5–50 in steps of 5.
    static let autoLowPowerModeThreshold = Key<Int>("autoLowPowerModeThreshold", default: 20)
    /// What BatFi changed when it turned Low Power Mode on for the battery, or nil while it
    /// holds nothing. Not a setting — nothing in the UI reads or writes it.
    ///
    /// Low Power Mode is the user's setting and carries no record of who turned it on, so
    /// this is that record: it holds the value to give back, and it is what lets BatFi tell
    /// its own Low Power Mode from one the user chose. See `AutoLowPowerModePolicy`.
    /// Persisted, and written before the setting is, because the setting outlives the
    /// process.
    static let autoLowPowerModeRecord = Key<AutoLowPowerModeRecord?>("autoLowPowerModeRecord", default: nil)
    /// Whether BatFi is staying out of Low Power Mode until the Mac is next on the charger,
    /// because the user changed one BatFi had turned on. Also not a setting.
    static let autoLowPowerModeYieldedUntilCharge = Key<Bool>("autoLowPowerModeYieldedUntilCharge", default: false)
    /// Whether the user has been told, during this discharge, that BatFi turned Low Power
    /// Mode on. Also not a setting. Persisted, so that turning it on again after a relaunch —
    /// every update quits and relaunches — is not announced again. See
    /// `AutoLowPowerModeEvaluation.announcement` for where a discharge ends.
    static let autoLowPowerModeAnnouncedThisDischarge = Key<Bool>("autoLowPowerModeAnnouncedThisDischarge", default: false)

    // Apps slowed down on battery
    /// The master switch for slowing down the apps in `slowedOnBatteryApps` on battery.
    static let slowDownAppsOnBattery = Key<Bool>("slowDownAppsOnBattery", default: true)
    /// The apps the user slows down on battery, by bundle identifier, and how much of the time.
    static let slowedOnBatteryApps = Key<[String: SlowDownMode]>("slowedOnBatteryApps", default: [:])
    /// The processes BatFi has confined to the efficiency cores and not yet given back. Not
    /// a setting — nothing in the UI reads or writes it. The menu learns which apps are
    /// slowed right now from the throttle manager instead; see `SlowDownStatus`.
    ///
    /// The kernel cannot be asked whether a process is demoted, so this is the only record of
    /// what BatFi has to give back. Persisted because a demotion outlives BatFi: after a
    /// crash, the next launch restores what this says was left demoted. See
    /// `BackgroundThrottlePolicy`.
    static let backgroundThrottleLedger = Key<[ThrottleLedgerEntry]>("backgroundThrottleLedger", default: [])

    /// The keys that are records rather than settings, and so survive "Reset settings".
    ///
    /// Each one remembers something BatFi did to the system, or checked about it, that a
    /// reset of the user's choices does not undo. Forgetting `systemSleepDisabledByBatFi`
    /// leaves a flag BatFi raised with nothing that knows to lower it. Forgetting
    /// `didCheckForSleepDisableLeftByAnEarlierVersion` re-runs a look meant to happen once,
    /// on the upgrade, which can then mistake a flag the user set by hand for one an earlier
    /// BatFi left behind — and clear it. Forgetting `autoLowPowerModeRecord` leaves Low
    /// Power Mode on with nothing that knows to give it back. Forgetting
    /// `autoLowPowerModeYieldedUntilCharge` lets BatFi turn back on, mid-discharge, a Low
    /// Power Mode the user has just turned off. Forgetting
    /// `autoLowPowerModeAnnouncedThisDischarge` tells the user again, mid-discharge, what
    /// they were told already. Forgetting `backgroundThrottleLedger` leaves apps confined to
    /// the efficiency cores with nothing that knows to give them back.
    ///
    /// A new key that records system state BatFi must undo belongs here.
    static let stateKeysPreservedAcrossReset: [Defaults.Keys] = [
        systemSleepDisabledByBatFi,
        didCheckForSleepDisableLeftByAnEarlierVersion,
        autoLowPowerModeRecord,
        autoLowPowerModeYieldedUntilCharge,
        autoLowPowerModeAnnouncedThisDischarge,
        backgroundThrottleLedger,
    ]

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
    // Off everywhere, debug builds included: it is opt-in from Settings › General.
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
    // Stored as the raw string rather than the enum: the key predates this module's
    // dependency on `Shared`. Nil means unresolved, which `ChargeLimitRange.lowestSelectable` answers with
    // the permissive 50% floor — the same answer a Mac that has never been asked deserves.
    static let lastKnownChargeBackend = Key<String?>("lastKnownChargeBackend", default: nil)

    static let highEnergyImpactProcessesThreshold = Key<Int>("highEnergyImpactProcessesThreshold", default: 500)
    static let highEnergyImpactProcessesDuration = Key<TimeInterval>("highEnergyImpactProcessesDuration", default: 180)
    static let highEnergyImpactProcessesCapacity = Key<Int>("highEnergyImpactProcessesCapacity", default: 5)

    static let sendAnalytics = Key<Bool>(AnalyticsPreference.name, default: AnalyticsPreference.defaultValue)

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

    // free trial notifications: the end date of the trial each was last sent for, so each is
    // sent once per trial, and again for a trial given a new end date. See `TrialNotice`.
    static let trialDayBeforeNoticeSentForEnd = Key<Date?>("trialDayBeforeNoticeSentForEnd", default: nil)
    static let trialEndedNoticeSentForEnd = Key<Date?>("trialEndedNoticeSentForEnd", default: nil)
    /// The end date of the trial this install last saw running; the end notice is sent only
    /// for that trial, never for one first met already ended.
    static let trialSeenRunningUntil = Key<Date?>("trialSeenRunningUntil", default: nil)

    // Calendar / automation
    static let automationEnabled = Key<Bool>("automationEnabled", default: false)
    static let automationRules = Key<[AutomationRule]>("automationRules", default: [])
    /// Written by the automation engine: the id of the rule currently driving charging
    /// (empty when none). Read by the settings pane and menu to show an ACTIVE badge.
    static let automationActiveRuleID = Key<String>("automationActiveRuleID", default: "")
}
