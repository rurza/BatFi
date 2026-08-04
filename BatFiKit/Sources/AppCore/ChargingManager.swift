//
//  ChargingManager.swift
//
//
//  Created by Adam on 04/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import IOKit.pwr_mgt
import License
import os
import Settings
import Shared

public actor ChargingManager: ChargingModeManager {
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.sleepAssertionClient) private var sleepAssertionClient
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.date) private var date

    private var computerIsAsleep = false
    private lazy var logger = Logger(category: "Charging Manager")

    private var powerStatePullingTask: Task<Void, Never>?
    private var licenseModel: LicenseModel?

    private var lastChargerConnectedStatus: ChargerConnectedStatus?

    /// The last request/applied pair `applyChargeLimit(_:)` reported, so a mismatch is
    /// reported as an event rather than as a state. Under the system charge limit a
    /// mismatch is the permanent steady state for anyone whose limit is below 80%, and
    /// this runs on every status update. Cleared in `disengage()` so re-engaging says it
    /// once again.
    private var lastReportedChargeLimit: AppliedChargeLimit?

    /// The last failure `applyChargeLimit(_:)` reported, for the same reason and with the
    /// same lifetime. A limit that cannot be applied usually cannot be applied for a reason
    /// that lasts as long as the process — the wrong firmware, a PowerUI selector this build
    /// does not expose — so without this the warning and its breadcrumb repeat on every
    /// status update forever on precisely the machines whose reports are worth having.
    private var lastReportedChargeLimitFailure: ChargeLimitFailure?

    /// Whether "we don't know if the lid is opened" has already been said since the lid was
    /// last known. Same reason as the two above: a Mac whose firmware exposes no lid key
    /// never leaves that state, and `fetchLidStatus()` runs on every status update, so
    /// without this it emits a notice and a Sentry breadcrumb once a minute forever.
    /// Cleared as soon as a lid value is read, so a transient unknown that returns is an
    /// event again.
    private var hasReportedUnknownLid = false

    /// Whether "hot-battery protection is switched on and there is no temperature to check
    /// it against" has already been said. Battery temperature became optional in Phase 1,
    /// and the argument for that — "strictly safer than today, where a missing temperature
    /// meant no charging decisions happened at all" — does not hold for this one feature.
    /// Before, a missing reading threw, the stream yielded nothing and BatFi wrote no SMC
    /// state at all. Now BatFi actively manages charging with the cutout bypassed, and
    /// nothing anywhere says so: the Advanced pane toggle still reads ON, the battery info
    /// view simply hides the row, and `logAvailableBatteryProperties` only fires for the
    /// three *required* fields. A safety feature that has silently stopped working has to
    /// be visible in a bug report.
    ///
    /// Reported on change rather than per pass, like the three above: on firmware that
    /// renamed the key this is a permanent steady state, and `updateStatus` runs several
    /// times a minute.
    private var hasReportedMissingBatteryTemperature = false

    /// The resolved charge backend, cached for the life of the process.
    ///
    /// Safe to cache and not merely convenient: a backend is a property of the firmware,
    /// and firmware is reflashed only by a macOS install — which restarts this process —
    /// and is never rolled back by a downgrade. It cannot change while BatFi runs. Stays
    /// nil while unresolved, so a helper that was not reachable yet is asked again on the
    /// next pass rather than answered by guessing.
    private var cachedChargeBackend: ChargeBackend?

    public init() {}

    /// Whether asking the helper to pause charging would actually pause it on this Mac.
    ///
    /// `true` while the backend is still unknown. Every Mac that works today can pause,
    /// and the honest failure here is to attempt it and have the helper report what
    /// happened — not to withhold a pause from a machine that supports one because the
    /// first diagnostics call had not landed yet.
    private func backendCanPauseChargingOnDemand() async -> Bool {
        if let cachedChargeBackend { return cachedChargeBackend.canPauseChargingOnDemand }
        // `try?` over a throwing call that already returns an optional nests two levels.
        guard let diagnostics = (try? await chargingClient.chargingDiagnostics()) ?? nil,
              let backend = ChargeBackend(rawValue: diagnostics.backend) else { return true }
        cachedChargeBackend = backend
        return backend.canPauseChargingOnDemand
    }

    public func setUpObserving() {
        assert(licenseModel != nil)
        Task {
            for await (
                (
                    (userTempChargingMode, powerState)
                ),
                (
                    (inhibitOnSleep, disableSleepDuringDischarge),
                    (preventAutomaticSleep, temperature),
                    (chargeLimit, manageCharging, allowDischarging)
                )
            ) in combineLatest(
                combineLatest(
                    appChargingState.userTempOverrideDidChange(),
                    powerSourceClient.powerSourceChanges()
                ),
                combineLatest(
                    combineLatest(
                        defaults.observe(.turnOnInhibitingChargingWhenGoingToSleep),
                        defaults.observe(.disableSleepDuringDischarging)
                    ),
                    combineLatest(
                        defaults.observe(.disableSleep),
                        defaults.observe(.temperatureSwitch)
                    ),
                    combineLatest(
                        defaults.observe(.chargeLimit),
                        defaults.observe(.manageCharging),
                        defaults.observe(.allowDischargingFullBattery)
                    )
                )
            ).debounce(for: .milliseconds(100), clock: AnyClock(self.clock)) {
                await updateStatus(
                    powerState: powerState,
                    userTempChargingMode: userTempChargingMode,
                    chargeLimit: chargeLimit,
                    manageCharging: manageCharging,
                    allowDischarging: allowDischarging,
                    preventAutomaticSleep: preventAutomaticSleep,
                    turnOffChargingWithHotBattery: temperature,
                    inhibitChargingOnSleep: inhibitOnSleep,
                    disableSleepDuringDischarge: disableSleepDuringDischarge
                )
            }
            logger.warning("The main loop did quit")
        }

        Task {
            for await sleepNote in sleepClient.observeMacSleepStatus() {
                guard defaults.value(.manageCharging) else { continue }
                switch sleepNote {
                case .willSleep:
                    computerIsAsleep = true
                    logger.debug("Mac is going to sleep")
                    let appChargingMode = await appChargingState.currentAppChargingMode()
                    let currentMode = appChargingMode.mode
                    let powerState = try? await powerSourceClient.currentPowerSourceState()
                    let currentLimit = appChargingMode.userTempOverride?.limit ?? defaults.value(.chargeLimit)
                    let tempOverride = appChargingMode.userTempOverride != nil
                    let inhibitOnSleep = defaults.value(.turnOnInhibitingChargingWhenGoingToSleep)

                    if powerState?.batteryLevel ?? 0 < currentLimit,
                        inhibitOnSleep, !tempOverride {
                        // Not attempted where a pause is not expressible. Under the
                        // firmware range the limit is already in the firmware's hands and
                        // stays in force for the whole sleep with no BatFi process
                        // running, so there is nothing this hook can add — and asking
                        // anyway would succeed without doing anything and leave the app
                        // reporting `.inhibit` on a Mac that carries on charging.
                        if await backendCanPauseChargingOnDemand() {
                            logger.notice("current mode: \(appChargingMode), turn inhibit on sleep: \(inhibitOnSleep)")
                            await inhibitCharging(chargerConnected: true, currentMode: currentMode)
                        } else {
                            logger.notice("Sleeping without a pause: this Mac's charge mechanism holds the limit itself")
                        }
                    }
                case .didWake:
                    logger.notice("Mac did wake up")
                    computerIsAsleep = false
                    await fetchAndUpdateAppChargingState()
                    await updateStatusWithCurrentState()
                }
            }
        }

        Task {
            for await _ in screenParametersClient.screenDidChangeParameters() {
                guard defaults.value(.manageCharging) else { continue }
                await fetchAndUpdateAppChargingState()
                await updateStatusWithCurrentState()
            }
        }

        Task {
            for await _ in await licenseModel!.stateChanges() {
                await updateStatusWithCurrentState()
            }
        }

        Task {
            for await _ in appChargingState.automationLimitDidChange() {
                logger.debug("Automation limit changed, re-evaluating charging")
                await updateStatusWithCurrentState()
            }
        }
    }

    public func setLicenseModel(_ licenseModel: LicenseModel) {
        self.licenseModel = licenseModel
    }

    public func appWillQuit() async {
        try? await chargingClient.restoreSystemDefaults()
        try? await sleepAssertionClient.disableSleep(false)
        await restoreSleepifNeeded()
    }

    nonisolated 
    public func forceCharge() {
        Task {
            await appChargingState.setTempOverride(.init(limit: 100))
        }
    }

    nonisolated public func stopForceCharge() {
        removeTempOverride()
    }

    nonisolated public func dischargeBattery() {
        dischargeBattery(to: 0)
    }

    nonisolated public func inhibitCharging() {
        Task {
            let powerState = try await powerSourceClient.currentPowerSourceState()
            await appChargingState.setTempOverride(.init(limit: powerState.batteryLevel))
        }
    }

    nonisolated public func dischargeBattery(to limit: Int) {
        guard limit >= 0, limit <= 100 else { return }
        Task {
            await appChargingState.setTempOverride(.init(limit: limit))
        }
    }

    nonisolated public func stopDischargingBattery() {
        removeTempOverride()
    }

    nonisolated public func stopOverride() {
        removeTempOverride()
    }

    nonisolated private func removeTempOverride() {
        Task {
            await appChargingState.setTempOverride(nil)
        }
    }

    private func startPullingPowerStateIfNeeded() async {
        guard powerStatePullingTask == nil else { return }
        powerStatePullingTask = Task { [weak self] in
            guard let self else { return }
            await analytics.addBreadcrumb(category: .chargingManager, message: "started pulling power state")
            while !Task.isCancelled {
                #if DEBUG
                try? await clock.sleep(for: .seconds(3))
                #else
                try? await clock.sleep(for: .seconds(30))
                #endif
                await updateStatusWithCurrentState()
            }
        }
    }

    private func cancelPullingPowerStateTaskIfNeeded() async {
        guard powerStatePullingTask != nil else { return }
        await analytics.addBreadcrumb(category: .chargingManager, message: "pulling power state stopped")
        powerStatePullingTask?.cancel()
        powerStatePullingTask = nil
    }

    private func updateStatusWithCurrentState() async {
        let powerState = try? await powerSourceClient.currentPowerSourceState()
        let userTempChargingMode = await appChargingState.currentUserTempOverrideMode()
        logger.debug("\(#function). Battery level: \(powerState?.batteryLevel.description ?? "no power state"), Charge limit: \(self.defaults.value(.chargeLimit))")
        if let powerState {
            let chargeLimit = defaults.value(.chargeLimit)
            let manageCharging = defaults.value(.manageCharging)
            let allowDischargingFullBattery = defaults.value(.allowDischargingFullBattery)
            let preventAutomaticSleep = defaults.value(.disableSleep)
            let batteryTemperature = defaults.value(.temperatureSwitch)
            let inhibitChargingOnSleep = defaults.value(.turnOnInhibitingChargingWhenGoingToSleep)
            let disableSleepDuringDischarge = defaults.value(.disableSleepDuringDischarging)

            await updateStatus(
                powerState: powerState,
                userTempChargingMode: userTempChargingMode,
                chargeLimit: Int(chargeLimit),
                manageCharging: manageCharging,
                allowDischarging: allowDischargingFullBattery,
                preventAutomaticSleep: preventAutomaticSleep,
                turnOffChargingWithHotBattery: batteryTemperature,
                inhibitChargingOnSleep: inhibitChargingOnSleep,
                disableSleepDuringDischarge: disableSleepDuringDischarge
            )
        }
    }

    private func updateStatus(
        powerState: PowerState,
        userTempChargingMode: UserTempChargingMode?,
        chargeLimit: Int,
        manageCharging: Bool,
        allowDischarging: Bool,
        preventAutomaticSleep: Bool,
        turnOffChargingWithHotBattery: Bool,
        inhibitChargingOnSleep: Bool,
        disableSleepDuringDischarge: Bool
    ) async {
        logger.debug("Update status")
        let appChargingMode = await appChargingState.currentAppChargingMode()
        let currentMode = appChargingMode.mode
        // Resolved rather than read straight off the reading, and the mode has to be in
        // hand first. On firmware with no `ExternalConnected` the connection is derived
        // from the power-source string, which reads "Battery Power" while BatFi is
        // force-discharging with the charger plugged in — see `ChargerConnection`.
        let chargerConnected = ChargerConnection.isConnected(
            reported: powerState.chargerConnected,
            isDerived: powerState.chargerConnectionIsDerived,
            appMode: currentMode
        )
        updateLastChargerConnectedStateIfNeeded(chargerConnected)

        // The automation engine can request a base charge limit. It overrides the user's
        // configured limit only when there's no manual temp override (which still wins).
        let automationLimit = await appChargingState.currentAutomationLimit()
        let effectiveChargeLimit = automationLimit ?? chargeLimit

        guard currentMode != .initial else {
            logger.debug("We don't have a mode yet")
            await analytics.addBreadcrumb(category: .chargingManager, message: "App mode is still set to initial")
            await fetchAndUpdateAppChargingState()
            return
        }

        guard await licenseModel?.hasValidLicense == true else {
            logger.notice("License not activated")
            await disengage(chargerConnected: chargerConnected)
            return
        }

        // The resolved value, not the raw one: releasing the prevent-automatic-sleep
        // assertion mid-discharge lets the Mac auto-sleep with force discharge latched in
        // the SMC.
        await setUpDelaySleep(
            preventAutomaticSleep &&
            powerState.batteryLevel < userTempChargingMode?.limit ?? effectiveChargeLimit &&
            chargerConnected
        )

        guard manageCharging else {
            logger.debug("Manage charging is turned off")
            await disengage(chargerConnected: chargerConnected)
            return
        }

        // Past both guards, so this only runs where BatFi is actually managing charging,
        // and ahead of the mode decision, so whichever branch is taken below the limit is
        // already in force. The value follows the same precedence used everywhere else a
        // target limit is worked out: a manual temp override beats the automation limit,
        // which beats the user's configured one.
        let requestedLimit = userTempChargingMode?.limit ?? effectiveChargeLimit
        // **The mode decision below branches on what was applied, not on what was asked
        // for**, and the two come apart under `.systemChargeLimit`, which cannot express a
        // limit below 80%. With a 55% limit and "allow discharging" on, branching on the
        // request produced a perpetual cycle on mains power: at 56% `56 > 55` engaged
        // `CHIE` and the battery drained on AC; at 55% `inhibitCharging` is a no-op under
        // that backend, so Apple's 80% limit resumed charging; at 56% it discharged again.
        // Cycling the battery indefinitely is the exact opposite of what the app is for.
        //
        // Falls back to the request when the apply failed, which is what it did before:
        // the mode decision is what every currently working Mac relies on and it must not
        // stop happening because Apple's limit could not be set.
        let effectiveLimitInForce = await applyChargeLimit(requestedLimit) ?? requestedLimit

        switch HotBatteryProtection.decision(
            isEnabled: turnOffChargingWithHotBattery,
            temperature: powerState.batteryTemperature,
            threshold: Constant.batteryTemperatureWarning
        ) {
        case .notEnabled, .withinLimits:
            hasReportedMissingBatteryTemperature = false
        case .tooHot(let batteryTemperature):
            hasReportedMissingBatteryTemperature = false
            logger.notice("Battery is hot")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Battery is hot, \(batteryTemperature)")
            // The same gate the sleep hook and its poll-side twin already carry, and this
            // arm needed it more than either: `temperatureSwitch` defaults to **true**, so
            // this was the one route to `inhibitCharging()` with no backend check on a
            // default-on path. Under `.firmwareRange` and `.systemChargeLimit` the inhibit
            // writes nothing, so the app's mode went to `.inhibit` regardless — the menu
            // bar said "Charging paused", `NotificationsManager` announced it, and the
            // MagSafe LED went green — while the Mac charged on at 45 °C. Reporting
            // `.inhibit` where nothing was inhibited is a worse failure than the missing
            // protection, which cannot be fixed and is disclosed instead.
            guard await backendCanPauseChargingOnDemand() else {
                logger.notice("Battery is hot but this Mac's charge mechanism cannot pause charging on demand; not claiming a pause")
                break
            }
            await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            return
        case .cutoutCannotFire:
            // Said once, loudly, and with a breadcrumb. This is the difference between
            // "the cutout did not need to fire" and "the cutout cannot fire", and only one
            // of those belongs in a bug report from a Mac that charged at 45 °C.
            if !hasReportedMissingBatteryTemperature {
                hasReportedMissingBatteryTemperature = true
                logger.error("Hot-battery protection is on but this Mac reports no battery temperature; charging is being managed with the cutout bypassed")
                await analytics.addBreadcrumb(
                    category: .chargingManager,
                    message: "Hot-battery protection is on but no battery temperature is available; the cutout cannot fire"
                )
            }
        }

        let isLidOpened: Bool
        if let lidOpened = await appChargingState.lidOpened() {
            isLidOpened = lidOpened
        } else {
            isLidOpened = await fetchLidStatus()
        }

        let isLidOpenedOrSleepDisabled = isLidOpened || disableSleepDuringDischarge

        let currentBatteryLevel = powerState.batteryLevel
        if let tempLimit = userTempChargingMode?.limit {
            logger.debug("User set temp limit to \(tempLimit)")
            // The override's own bookkeeping — "charge to full is done" and the
            // disconnect policy — keeps reading the value the *user* asked for. Only the
            // charge/hold/discharge comparisons move to what is in force; an override
            // raised from 55% to 80% is still a 55% override as far as removing it goes.
            if tempLimit >= 100, currentBatteryLevel >= 100 {
                logger.notice("Battery reached 100%, removing charge-to-full override")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Battery reached 100%, removing charge-to-full override")
                removeTempOverride()
                return await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            }
            handleRemovingTempOverrideOnDisconnect(
                chargerConnected: chargerConnected,
                batteryLevel: currentBatteryLevel,
                overrideLimit: tempLimit
            )
            if currentBatteryLevel > effectiveLimitInForce, isLidOpenedOrSleepDisabled {
                return await turnOnDischarging(
                    chargerConnected: chargerConnected,
                    disableSleep: disableSleepDuringDischarge,
                    currentMode: currentMode
                )
            } else if currentBatteryLevel < effectiveLimitInForce {
                return await turnOnCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            } else {
                return await inhibitCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            }
        } else {
            if currentBatteryLevel >= effectiveLimitInForce {
                if currentBatteryLevel > effectiveLimitInForce, allowDischarging, isLidOpenedOrSleepDisabled, !computerIsAsleep {
                    await turnOnDischarging(
                        chargerConnected: chargerConnected,
                        disableSleep: disableSleepDuringDischarge,
                        currentMode: currentMode
                    )
                    return
                } else {
                    await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
                }
            } else if inhibitChargingOnSleep, computerIsAsleep, await backendCanPauseChargingOnDemand() {
                // Same gate as the `willSleep` hook, and it has to be here too: a poll can
                // land while the Mac is asleep, and this branch is the one that would pin
                // the app to `.inhibit` for the rest of the sleep on a mechanism that
                // never paused anything.
                return await inhibitCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            } else {
                return await turnOnCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            }
        }
    }

    /// Puts the target limit in force through whichever mechanism the helper resolved.
    ///
    /// Under the inhibit backends this costs almost nothing — they express a limit as an
    /// inhibit, so the helper reads its cached backend and hands the requested value
    /// straight back — which is why one call site serves every backend. Under the system
    /// charge limit and the firmware range it is the only thing holding charge back at
    /// all: there is no inhibit write on that firmware, so without this the mode decision
    /// below would decide a mode nothing could enforce. Both of those hold a needs-write
    /// short-circuit helper-side, so a repeat call with an unchanged limit writes nothing.
    ///
    /// A failure is logged and swallowed deliberately. The mode decision that follows is
    /// what every currently working Mac relies on and it does not depend on this call, so
    /// aborting it because Apple's limit could not be set would regress machines that
    /// never needed the limit in the first place.
    ///
    /// Both arms report a *change* rather than a condition. The limit is applied on every
    /// status update, and both the mismatch and the failure it can report are steady states
    /// rather than events, so an unguarded log here is one line and one Sentry breadcrumb a
    /// minute for the life of the process. Each arm clears the other's memory, so a failure
    /// after a run of successes — or a mismatch after a run of failures — is a change and is
    /// said once more.
    /// - Returns: the limit actually in force, or nil when it could not be applied. The
    ///   mode decision in `updateStatus` branches on this rather than on the request — see
    ///   the comment there — so the value must not be swallowed even though the failure is.
    @discardableResult
    private func applyChargeLimit(_ limit: Int) async -> Int? {
        do {
            let applied = try await chargingClient.applyChargeLimit(limit)
            lastReportedChargeLimitFailure = nil
            // On change, not on inequality. Under the system charge limit a request the
            // mechanism cannot express — anything below 80%, which is most of the slider —
            // resolves to a raised value on *every* pass, so reporting the inequality would
            // emit a notice and burn a Sentry breadcrumb roughly once a minute, forever, on
            // exactly the machines whose bug reports are worth having. The mismatch itself
            // is still carried structurally by `ChargingDiagnostics.chargeLimitWasRaised`.
            let outcome = AppliedChargeLimit(requested: limit, applied: applied)
            if AppliedChargeLimit.shouldReport(outcome, lastReported: lastReportedChargeLimit) {
                lastReportedChargeLimit = outcome
                logger.notice("Charge limit \(limit, privacy: .public)% applied as \(applied, privacy: .public)%")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Charge limit \(limit)% applied as \(applied)%")
            }
            return applied
        } catch {
            let failure = ChargeLimitFailure(requested: limit, reason: String(describing: error))
            if ChargeLimitFailure.shouldReport(failure, lastReported: lastReportedChargeLimitFailure) {
                lastReportedChargeLimitFailure = failure
                lastReportedChargeLimit = nil
                logger.warning("Failed to apply charge limit \(limit, privacy: .public)%: \(error, privacy: .public)")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to apply charge limit. Error: \(error.localizedDescription)")
            }
            return nil
        }
    }

    private func disengage(chargerConnected: Bool) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        // BatFi is handing charging back, so the next limit it applies starts a new
        // episode and is worth reporting again even if it resolves — or fails — the same way.
        lastReportedChargeLimit = nil
        lastReportedChargeLimitFailure = nil
        logger.debug("Disengaging — restoring system defaults")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Disengaging — restoring system defaults")
        do {
            try await chargingClient.restoreSystemDefaults()
            await analytics.addBreadcrumb(category: .chargingManager, message: "System defaults restored")
        } catch {
            logger.warning("Failed to restore system defaults: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to restore system defaults. Error: \(error.localizedDescription)")
        }

        // Everything below runs whether or not the restore threw, and that is the fix.
        // `restoreSystemDefaults()` attempts its three writes independently and calls
        // `resetIfPossible()` before it rethrows, so by the time it throws the hardware has
        // already been put back — but it still rethrows, and under `.unsupported`
        // `enableCharging(true)` throws unconditionally. Sitting inside the `do` meant that
        // on a machine with no mechanism at all, and on any machine where one of the three
        // writes failed, turning "manage charging" off left the app reporting
        // `.inhibit`/`.forceDischarge` for the rest of the session, the MagSafe LED green,
        // and a sleep assertion held. `.charging` is the accurate report either way.
        if sleepAssertionMayBeHeldForDischarging {
            try? await sleepAssertionClient.disableSleep(false)
        }
        // BatFi is handing charging back, so it must not still be preventing automatic
        // sleep. The license-invalid guard in `updateStatus` returns through here *before*
        // reaching `setUpDelaySleep`, so without this a held prevent-automatic-sleep
        // assertion survived until quit.
        await restoreSleepifNeeded()
        await appChargingState.updateChargingMode(.charging)
    }

    /// Whether a discharge-related sleep assertion could be outstanding.
    ///
    /// The release sites used to be gated on `allowDischargingFullBattery` alone, so
    /// turning that off mid-discharge stranded the assertion with nothing left that would
    /// release it. Both settings that can *take* one are named here, so neither can be
    /// switched off out from under its own release. Still gated rather than unconditional:
    /// `disableSleep(false)` makes an XPC call, and this runs on every status update.
    private var sleepAssertionMayBeHeldForDischarging: Bool {
        defaults.value(.allowDischargingFullBattery) || defaults.value(.disableSleepDuringDischarging)
    }

    private func turnOnCharging(chargerConnected: Bool, currentMode: ChargingMode) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        logger.debug("Turning on charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on charging")
        do {
            try await chargingClient.turnOnAutoChargingMode()
            if sleepAssertionMayBeHeldForDischarging {
                try? await sleepAssertionClient.disableSleep(false)
            }
            await analytics.addBreadcrumb(category: .chargingManager, message: "Charging turned on")
            await appChargingState.updateChargingMode(.charging)
        } catch {
            logger.warning("Failed to turn on charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on charging. Error: \(error.localizedDescription)")
        }
    }

    private func inhibitCharging(chargerConnected: Bool, currentMode: ChargingMode) async {
        await updateChargerConnected(chargerConnected)
        logger.debug("Inhibiting charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibiting charging")
        do {
            try await chargingClient.inhibitCharging()
            if sleepAssertionMayBeHeldForDischarging {
                try? await sleepAssertionClient.disableSleep(false)
            }
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging turned on")
            await appChargingState.updateChargingMode(.inhibit)
            await startPullingPowerStateIfNeeded()
        } catch {
            logger.warning("Failed to inhibit charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to inhibit charging. Error: \(error.localizedDescription)")
        }
    }

    private func turnOnDischarging(chargerConnected: Bool, disableSleep: Bool, currentMode: ChargingMode) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        // Ahead of the assertion, not after it. Taking the assertion first and then
        // returning through this guard stranded it: nothing below runs, and every release
        // site is on a path this pass no longer reaches.
        guard chargerConnected else {
            logger.debug("Charger not connected, skipping discharging")
            try? await sleepAssertionClient.disableSleep(false)
            return
        }
        try? await sleepAssertionClient.disableSleep(disableSleep)
        if defaults.value(.disableSleepDuringDischarging) {
            try? await sleepAssertionClient.disableSleep(true)
        }
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on discharging")
        logger.debug("Turning on discharging")
        do {
            try await chargingClient.forceDischarge()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Discharging turned on")
            await appChargingState.updateChargingMode(.forceDischarge)

        } catch {
            logger.warning("Failed to turn on discharging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on discharging. Error: \(error.localizedDescription)")
        }
    }

    private func setUpDelaySleep(_ delay: Bool) async {
        if delay {
            await delaySleepIfNeeded()
        } else {
            await restoreSleepifNeeded()
        }
    }

    private func delaySleepIfNeeded() async {
        if await !sleepAssertionClient.preventsAutomaticSleep() {
            logger.notice("Preventing sleep")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Preventing sleep")
            await sleepAssertionClient.preventAutomaticSleepIfNeeded(true)
        }
    }

    private func restoreSleepifNeeded() async {
        if await sleepAssertionClient.preventsAutomaticSleep() {
            logger.notice("Restoring sleep")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Restoring sleep")
            await sleepAssertionClient.preventAutomaticSleepIfNeeded(false)
        }
    }

    private func fetchAndUpdateAppChargingState() async {
        do {
            logger.notice("Fetching charging state")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Fetching charging state")
            let powerState = try await powerSourceClient.currentPowerSourceState()
            let chargingStatus = try await chargingClient.chargingStatus()
            let userTempOverride = await appChargingState.currentUserTempOverrideMode()
            logger.notice("Current status: \(chargingStatus.description, privacy: .public)")

            let mode: ChargingMode
            if chargingStatus.forceDischarging {
                mode = .forceDischarge
            } else if chargingStatus.inhitbitCharging {
                mode = .inhibit
            } else if chargingStatus.isCharging {
                mode = .charging
            } else {
                mode = .inhibit
            }

            // Only when the helper actually read one. An unknown lid leaves the last known
            // answer — or `nil`, which `fetchLidStatus()` retries — rather than being
            // recorded as "closed", which would suppress discharging on a machine whose
            // firmware simply has no lid key.
            if let lidOpened = chargingStatus.lidOpened {
                await appChargingState.updateLidOpenedStatus(lidOpened)
            }
            await appChargingState.setAppChargingMode(
                .init(
                    mode: mode,
                    userTempOverride: userTempOverride,
                    chargerConnected: ChargerConnection.isConnected(
                        reported: powerState.chargerConnected,
                        isDerived: powerState.chargerConnectionIsDerived,
                        appMode: mode
                    )
                )
            )
            await updateStatusWithCurrentState()
        } catch {
            logger.error("Error fetching charging state: \(error)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Error fetching charging state: \(error.localizedDescription)")
        }
    }

    private func fetchLidStatus() async -> Bool {
        // Reported on change, not per pass. On a Mac whose firmware has no lid key the
        // stored state stays `nil` forever, so this runs on every status update — roughly
        // once a minute — and "unknown" is that machine's steady state rather than an
        // event. The re-ask itself is deliberate and stays: a key that failed transiently
        // has to be asked again. Only the noise is bounded.
        let reportUnknown = !hasReportedUnknownLid
        if reportUnknown {
            hasReportedUnknownLid = true
            logger.notice("We don't know if the lid is opened")
            await analytics.addBreadcrumb(category: .chargingManager, message: "We don't know if the lid is opened")
        }
        do {
            let chargingStatus = try await chargingClient.chargingStatus()
            guard let lidOpened = chargingStatus.lidOpened else {
                // Same answer this function's `catch` has always given when it could not
                // find out, and for the same reason: the caller needs a `Bool`, and the
                // stored state stays `nil` so the next pass asks again.
                if reportUnknown {
                    logger.notice("The helper could not read the lid state")
                }
                return false
            }
            await appChargingState.updateLidOpenedStatus(lidOpened)
            // Known again, so a later unknown is a change and is worth saying once more.
            hasReportedUnknownLid = false
            return lidOpened
        } catch {
            logger.notice("Failed to fetch lid status: \(error)")
            await analytics.captureError(error: error)
            return false
        }
    }

    private func updateChargerConnected(_ chargerConnected: Bool) async {
        await analytics.addBreadcrumb(category: .chargingManager, message: "Updating charger connected status")
        logger.notice("Updating charger connected status: \(chargerConnected)")
        await appChargingState.setChargerConnected(chargerConnected)
    }

    // MARK: - Last state of charger connected
    private func updateLastChargerConnectedStateIfNeeded(_ chargerConnected: Bool) {
        let newState = ChargerConnectedStatus(date: date.now, isConnected: chargerConnected)
        if let lastChargerConnectedStatus {
            if lastChargerConnectedStatus.isConnected != chargerConnected {
                logger.debug("Update last charger connected status: \(chargerConnected)")
                self.lastChargerConnectedStatus = newState
            }
        } else {
            self.lastChargerConnectedStatus = newState
        }
    }

    private var removeTempOverrideTask: Task<Void, Never>?

    private func handleRemovingTempOverrideOnDisconnect(chargerConnected: Bool, batteryLevel: Int, overrideLimit: Int) {
        let secondsSinceDisconnect: TimeInterval?
        if let disconnectStatus = lastChargerConnectedStatus, !disconnectStatus.isConnected {
            secondsSinceDisconnect = date.now.timeIntervalSince(disconnectStatus.date)
        } else {
            secondsSinceDisconnect = nil
        }

        switch TempOverrideDisconnectPolicy.decision(
            chargerConnected: chargerConnected,
            batteryLevel: batteryLevel,
            overrideLimit: overrideLimit,
            secondsSinceDisconnect: secondsSinceDisconnect
        ) {
        case .keep:
            if removeTempOverrideTask != nil {
                logger.debug("Keeping temp override, cancelling pending removal")
                removeTempOverrideTask?.cancel()
                removeTempOverrideTask = nil
            }
        case .removeNow:
            logger.notice("Charger disconnected long enough, removing temp override")
            removeTempOverride()
            removeTempOverrideTask?.cancel()
            removeTempOverrideTask = nil
        case .scheduleRemoval(let delay):
            guard removeTempOverrideTask == nil else { return }
            logger.debug("Charger disconnected, scheduling temp override removal in \(Int(delay))s")
            removeTempOverrideTask = Task {
                try? await clock.sleep(for: .seconds(delay), tolerance: .seconds(1))
                if !Task.isCancelled {
                    self.logger.notice("Removing temp override after prolonged charger disconnect")
                    self.removeTempOverride()
                    self.removeTempOverrideTask = nil
                }
            }
        }
    }
}
