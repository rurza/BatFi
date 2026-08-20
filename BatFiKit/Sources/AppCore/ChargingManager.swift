//
//  ChargingManager.swift
//
//
//  Created by Adam on 04/05/2023.
//

import AppKit
import AppShared
import AsyncAlgorithms
import Defaults
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import IOKit.pwr_mgt
import L10n
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
    @Dependency(\.helperHealthClient) private var helperHealthClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.date) private var date
    @Dependency(\.userNotificationsClient) private var userNotificationsClient
    @Dependency(\.powerDistributionClient) private var powerDistributionClient

    /// The run of readings that contradict the hold BatFi's configuration implies.
    ///
    /// Everything else here re-issues commands on a schedule and believes what it wrote.
    /// This is the one thing that asks the battery, so that a limit retired underneath BatFi
    /// — by macOS, by another app taking the mechanism over, by firmware doing something
    /// nobody has characterised — is noticed rather than reported as applied forever.
    private var driftMonitor = ChargeHoldDriftMonitor()
    private var nudgeMonitor = ChargeResumeNudgeMonitor()
    /// The firmware's last answer to "is anything holding charge right now", and when it was
    /// asked. Throttled because asking is an XPC round trip into
    /// `SMCService.chargingDiagnostics()`, which opens the SMC, reads `CHNC`, queries PowerUI
    /// and probes three more keys — on the same actor that serves `applyChargeLimit`.
    private var lastHoldAttribution: Bool?
    private var lastHoldAttributionAt: Date?

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
    /// Whether the hardware may no longer be holding what it was last told.
    ///
    /// The charging appliers re-issue their command on every status update, and status
    /// updates are driven by `powerSourceChanges()` — which fires continuously. Measured on
    /// one machine that was doing nothing but holding a limit: 2,748 XPC round trips into
    /// the helper and back in 2h20m, one every 3.2 seconds, every one of them re-sending a
    /// command the SMC was already holding and answering "no SMC write needed".
    ///
    /// Re-sending was never the point, though — it was insurance against the SMC being put
    /// back to defaults by something other than BatFi. That does happen, but it happens at
    /// identifiable moments, not continuously, so the insurance is kept and the polling
    /// dropped: anything that could have reset the hardware sets this, and the next applier
    /// re-issues unconditionally regardless of what the app believes the mode to be.
    private var hardwareStateMayBeStale = true
    /// When the last charging command actually reached the hardware.
    private var lastAppliedAt: Date?
    /// How long a command is trusted to still be in force before it is re-sent regardless.
    ///
    /// The named events — sleep, wake, a helper restart, the charger moving — cover every
    /// way the SMC is *known* to lose what BatFi put there. This covers the rest: firmware
    /// doing something unannounced, a mechanism quietly declining a write, anything not
    /// thought of here. The old code had that insurance too, at one round trip every 3.2
    /// seconds; five minutes buys the same protection for about a thousandth of the traffic,
    /// and the worst case it allows — a limit unenforced for a few minutes on a battery that
    /// moves by roughly a percent in that time — is not a worst case worth 27,000 XPC calls
    /// a day to avoid.
    private static let reassertionInterval: TimeInterval = 300
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
        // `try?` flattens the optional the call already returns, so there is one level
        // here, not two.
        guard let diagnostics = try? await chargingClient.chargingDiagnostics(),
              let backend = ChargeBackend(rawValue: diagnostics.backend) else { return true }
        cachedChargeBackend = backend
        return backend.canPauseChargingOnDemand
    }

    /// Whether macOS drains the battery to the limit itself on this Mac.
    ///
    /// **`false` while the backend is unknown** — the opposite default to
    /// `backendCanPauseChargingOnDemand`, and right for the same reason that one is `true`.
    /// Both keep BatFi doing what it has always done until it learns otherwise: there,
    /// attempting a pause; here, performing its own discharge. Withholding a discharge from a
    /// Mac that needs BatFi to do it, because the first diagnostics call had not landed, would
    /// leave the battery sitting above the user's limit with nothing coming to fix it.
    private func systemDischargesToLimitItself() async -> Bool {
        await chargeBackend()?.dischargesToLimitItself ?? false
    }

    /// The resolved backend, memoized for the life of the process — a backend is a property
    /// of the firmware, and firmware is reflashed only by a macOS install, which restarts
    /// this process.
    private func chargeBackend() async -> ChargeBackend? {
        if let cachedChargeBackend { return cachedChargeBackend }
        guard let diagnostics = try? await chargingClient.chargingDiagnostics(),
              let backend = ChargeBackend(rawValue: diagnostics.backend) else { return nil }
        cachedChargeBackend = backend
        // Said once per process, at `notice`, because every report that arrives without it
        // starts with a round of questions: which mechanism this Mac has, what firmware it
        // is on, and whether the limit in force is the one that was asked for. All of it is
        // already in hand here.
        logger.notice(
            "Charge mechanism: \(backend.rawValue, privacy: .public), firmware \(diagnostics.firmwareVersion ?? "unknown", privacy: .public), requested limit \(diagnostics.requestedChargeLimit.map(String.init) ?? "n/a", privacy: .public), applied \(diagnostics.appliedChargeLimit.map(String.init) ?? "n/a", privacy: .public), force discharge \(diagnostics.forceDischargeAvailable.map(String.init) ?? "unknown", privacy: .public), not charging because: \(diagnostics.notChargingReasons.joined(separator: ", "), privacy: .public)"
        )
        return backend
    }

    /// Compares the battery against the hold BatFi's configuration implies, and puts the
    /// limit back when the two disagree.
    ///
    /// The check every other path here is missing. The appliers re-issue what they last
    /// wrote and the helper skips a write whose value it has already recorded, so a limit
    /// that stops being enforced stays invisible: powerd retires its policy whenever Apple's
    /// charge limit changes underneath, the `.firmwareRange` band is SMC keys anything with
    /// root can clear, and another charge-limiting app takes the same mechanisms over by
    /// design. None of those announce themselves, and all of them leave BatFi reporting a
    /// limit it once applied.
    private func checkForChargeHoldDrift(
        powerState: PowerState,
        chargerConnected: Bool,
        requestedLimit: Int,
        limitInForce: Int,
        currentMode: ChargingMode
    ) async {
        // BatFi's own discharge has the fault's exact shape — charger in, battery above the
        // limit, going down — and is deliberate. The firmware would attribute it
        // (`adapterDisabledCH0I`), but not asking is cheaper and does not depend on that key
        // being readable on this machine.
        guard currentMode != .forceDischarge else {
            driftMonitor = ChargeHoldDriftMonitor()
            return
        }

        let now = date.now
        let holdIsAttributed = await holdAttribution(
            chargerConnected: chargerConnected,
            isCharging: powerState.isCharging,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            now: now
        )
        let isDrifting = ChargeHoldDrift.isDrifting(
            chargerConnected: chargerConnected,
            isCharging: powerState.isCharging,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            holdIsAttributed: holdIsAttributed
        )

        let response = driftMonitor.record(isDrifting: isDrifting, at: now)
        guard response != .none else {
            if isDrifting {
                // The first minute of a run. Logged so that a fault which corrects itself
                // still leaves a trace — those are the ones that are otherwise impossible
                // to tell from a user misremembering.
                logger.debug("Battery contradicts the hold at \(powerState.batteryLevel, privacy: .public)% against \(limitInForce, privacy: .public)%; watching before acting")
            }
            return
        }

        let attribution = holdIsAttributed.map(String.init) ?? "not asked"
        logger.error("Charge limit is not holding: battery \(powerState.batteryLevel, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, charging \(powerState.isCharging, privacy: .public), firmware attributes a hold: \(attribution, privacy: .public). Reasserting \(requestedLimit, privacy: .public)%")
        await analytics.addBreadcrumb(
            category: .chargingManager,
            message: "Charge limit not holding at \(powerState.batteryLevel)% against \(limitInForce)%; reasserting"
        )
        // Whatever took the limit may have taken the SMC mode with it, so the next applier
        // re-issues its command too rather than trusting what it last wrote.
        hardwareStateMayBeStale = true
        do {
            let applied = try await chargingClient.reassertChargeLimit(requestedLimit)
            logger.notice("Charge limit reasserted; \(applied, privacy: .public)% now in force")
        } catch {
            logger.error("Reasserting charge limit \(requestedLimit, privacy: .public)% failed: \(error, privacy: .public)")
        }

        if response == .warnTheUser {
            await warnThatTheChargeLimitIsNotHolding(limit: requestedLimit)
        }
    }

    /// Whether the firmware names something holding charge back right now, or nil where it
    /// was not asked.
    ///
    /// Asked for either steady state in which nothing is charging on the charger and the
    /// battery is not resting exactly at its limit — above it for the drift question, below
    /// it for `SystemChargeHold` — and only on backends whose hold the firmware attributes at
    /// all. Nil is "no evidence" everywhere else, never "nothing is holding".
    ///
    /// Exactly at the limit is excluded because that is the healthy resting state of every
    /// working Mac and neither question needs an answer there. The 300s throttle is shared,
    /// so both callers in one pass cost one SMC round trip.
    private func holdAttribution(
        chargerConnected: Bool,
        isCharging: Bool,
        batteryLevel: Int,
        limitInForce: Int,
        now: Date
    ) async -> Bool? {
        guard chargerConnected, !isCharging, batteryLevel != limitInForce else { return nil }
        guard let backend = await chargeBackend(), backend.attributesChargeHolds else { return nil }
        if let lastHoldAttributionAt,
           now.timeIntervalSince(lastHoldAttributionAt) < ChargeHoldDriftMonitor.attributionInterval {
            return lastHoldAttribution
        }
        lastHoldAttributionAt = now
        guard let diagnostics = try? await chargingClient.chargingDiagnostics() else {
            // A helper that could not answer has not said "nothing is holding".
            lastHoldAttribution = nil
            return nil
        }
        let attributed = diagnostics.notChargingReasons
            .compactMap(NotChargingReason.init(rawValue:))
            .contains(where: \.holdsChargeBack)
        lastHoldAttribution = attributed
        logger.debug("Firmware not-charging reasons: \(diagnostics.notChargingReasons.joined(separator: ", "), privacy: .public); holds charge: \(attributed, privacy: .public)")
        return attributed
    }

    /// Tells the user, once per run, that the limit they set is not being honoured.
    private func warnThatTheChargeLimitIsNotHolding(limit: Int) async {
        guard await userNotificationsClient.requestAuthorization() == true else { return }
        let percentage = percentageFormatter.string(from: NSNumber(value: Double(limit) / 100)) ?? "\(limit)%"
        do {
            try await userNotificationsClient.showUserNotification(
                title: L10n.Notifications.Notification.Title.chargeLimitNotHolding,
                body: L10n.Notifications.Notification.Body.chargeLimitNotHolding(percentage),
                identifier: "software.micropixels.BatFi.notifications.chargeLimitNotHolding",
                threadIdentifier: "Charge limit",
                delay: nil
            )
        } catch {
            logger.error("Could not post the charge-limit warning: \(error, privacy: .public)")
        }
    }

    public func setUpObserving() {
        assert(licenseModel != nil)
        observeHelperHealth()
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
                    // The inhibit below is the whole reason this hook exists; it must go out
                    // even if the app already believes charging is inhibited.
                    invalidateHardwareState()
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
                    // A sleep/wake cycle is the classic way for the SMC to come back
                    // holding something BatFi did not put there.
                    invalidateHardwareState()
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
        await setSleepDisabled(false)
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
            guard let powerState = try? await powerSourceClient.currentPowerSourceState() else { return }
            await appChargingState.setTempOverride(.init(limit: powerState.batteryLevel))
        }
    }

    /// Where the menu item and the `.dischargeBattery` hotkey actually converge.
    ///
    /// The menu reaches `ChargingModeManager`, which `App` satisfies with the manager itself
    /// rather than with `App` — so a gate in the app layer covered the hotkey and nothing else.
    /// It belongs here, below both.
    nonisolated public func dischargeBattery(to limit: Int) {
        guard limit >= 0, limit <= 100 else { return }
        Task {
            guard await confirmManualDischargeIfNeeded() else { return }
            await appChargingState.setTempOverride(.init(limit: limit))
        }
    }

    /// Discloses, once, that a manual discharge stops this Mac sleeping at all — and returns
    /// whether the user still wants it. Cancel means nothing happens: no override, no `pmset`.
    private func confirmManualDischargeIfNeeded() async -> Bool {
        guard ManualDischargeSleepNotice.shouldShow(
            backendOwnsDischarge: await systemDischargesToLimitItself(),
            userSuppressed: Defaults[.suppressManualDischargeSleepNotice]
        ) else { return true }
        return await MainActor.run {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.Notifications.Alert.Title.manualDischargeDisablesSleep
            alert.informativeText = L10n.Notifications.Alert.InformativeText.manualDischargeDisablesSleep
            alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.runOnBattery)
            alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.cancel)
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = L10n.Notifications.Alert.Button.Label.dontShowAgain
            // The app is an accessory, so the alert can otherwise open behind whatever is in
            // front and wait there for a click nobody knows to give.
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            // Recorded whichever button was pressed: the checkbox is about the alert, not
            // about the discharge.
            if alert.suppressionButton?.state == .on {
                Defaults[.suppressManualDischargeSleepNotice] = true
            }
            return response == .alertFirstButtonReturn
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

    /// Re-drives the charging state when the helper becomes reachable again.
    ///
    /// Without this the app only half-recovers. The main loop below is edge-triggered on
    /// power-source and defaults changes, and a helper coming back is neither, so the mode
    /// stayed latched at `.initial` — and the status item with it — until the next relaunch.
    private func observeHelperHealth() {
        Task {
            var wasHealthy = false
            for await health in helperHealthClient.observeHealth() {
                defer { wasHealthy = health.isHealthy }
                guard health.isHealthy, !wasHealthy else { continue }
                logger.notice("Helper is reachable again; re-driving charging state")
                // A helper that went away and came back is a new process that has just
                // restored system defaults on its way out of the old one. Whatever the app
                // believes is in force, the hardware is not holding it.
                invalidateHardwareState()
                await updateStatusWithCurrentState()
            }
        }
    }

    private func updateStatusWithCurrentState() async {
        // Nothing to drive while the app is deliberately taking the daemon down to reclaim
        // it. Every call in that window fails — the helper has been asked to quit and the
        // registration is being rewritten — and failing loudly is the least of it: the mode
        // churns as the calls error out, which posts charging-status notifications the user
        // has no way to interpret, and a limit or discharge command issued a moment before
        // the quit lands on the *other* copy's helper, which is precisely the daemon this
        // app has already decided it should not be driving.
        //
        // Skipped, not queued. `observeHelperHealth()` re-drives from the current power
        // state the moment a helper of ours answers, so the correct limit is applied from
        // fresh readings rather than from whatever was true before the outage.
        guard await !helperHealthClient.isReclaimingHelper() else {
            logger.debug("Reclaiming the helper; not driving charging until it answers")
            return
        }
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

        // Asked of the battery rather than of the mechanism, and asked after the limit has
        // been put in force so that both are read on the same pass.
        await checkForChargeHoldDrift(
            powerState: powerState,
            chargerConnected: chargerConnected,
            requestedLimit: requestedLimit,
            limitInForce: effectiveLimitInForce,
            currentMode: currentMode
        )

        // Answered once per pass, here rather than inside the mode decision, and answered on
        // **every** pass rather than only on the branch that consumes it. The monitor below
        // needs the clean readings as much as the held ones: its clock is reset by them, and a
        // clock left half-elapsed by a pass that never asked would fire a write within seconds
        // of the next dip instead of after a minute of it.
        let systemIsHoldingBelowLimit = await systemIsHoldingChargeBelowLimit(
            powerState: powerState,
            chargerConnected: chargerConnected,
            limitInForce: effectiveLimitInForce,
            currentMode: currentMode
        )
        await checkForChargeResumeStall(
            isHolding: systemIsHoldingBelowLimit,
            target: requestedLimit,
            now: date.now
        )

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

        // A manual discharge on a mechanism that drains to the limit itself is the only thing
        // left driving the SMC, and it takes the adapter out of the circuit — so BatFi disables
        // sleep outright for its duration. That is what lets the lid be closed on an external
        // display, which `pmset -a disablesleep` buys and an IOPM assertion explicitly does not.
        // Disclosed once by the alert behind `ManualDischargeSleepNotice`.
        // Bound on its own rather than folded into an `&&`: the right-hand side of a
        // short-circuiting operator is an autoclosure and cannot be async. The cheap
        // short-circuit is kept by only asking when an override is actually present.
        let manualDischargeDisablesSleep: Bool
        if userTempChargingMode != nil {
            manualDischargeDisablesSleep = await systemDischargesToLimitItself()
        } else {
            manualDischargeDisablesSleep = false
        }
        let sleepIsDisabledForDischarge = disableSleepDuringDischarge || manualDischargeDisablesSleep
        let isLidOpenedOrSleepDisabled = isLidOpened || sleepIsDisabledForDischarge

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
            // Symmetric to the charge-to-full removal above, and needed for the same reason
            // the discharge arm below had to stop reading the applied limit. Where charging
            // is held at a percentage there is no way to *keep* a battery below 80%: the
            // inhibit writes nothing, so BatFi would discharge to the target, let Apple's
            // limit charge it back, and discharge again — cycling the battery on mains
            // power, which is precisely what this app exists to prevent. The override has
            // met its goal, so it is retired rather than left oscillating. Backends that can
            // pause charging on demand hold the target exactly as before.
            //
            // `tempLimit > 0` deliberately: "Run on Battery" is a 0% override and is meant
            // to keep discharging until the charger is unplugged or the user cancels it.
            if currentBatteryLevel <= tempLimit, tempLimit > 0, tempLimit < 100,
               await !backendCanPauseChargingOnDemand() {
                logger.notice("Discharge target reached and this Mac's charge mechanism cannot hold it; removing the override")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Discharge target reached on a backend that cannot hold it; removing override")
                removeTempOverride()
                return await turnOnCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            }
            handleRemovingTempOverrideOnDisconnect(
                chargerConnected: chargerConnected,
                batteryLevel: currentBatteryLevel,
                overrideLimit: tempLimit
            )
            // The discharge decision reads the limit the *user asked for*, not the one the
            // charge mechanism could express — and that difference is the whole feature on
            // firmware that holds a percentage. Discharging is force discharge over `CHIE`,
            // a separate mechanism this Mac still has; the charge limit cannot express
            // anything under 80%, so under `.systemChargeLimit` "Run on Battery" (a 0%
            // override) came back applied as 80%, and this branch then read a 61% battery
            // as "below the limit, start charging" — the exact opposite of the request, with
            // the menu still showing the override ticked.
            //
            // Only this arm moves back to the request. The charge arm below keeps reading
            // what is actually in force, because that is what governs charging and is what
            // stopped the discharge/charge cycling described above.
            if currentBatteryLevel > tempLimit, isLidOpenedOrSleepDisabled {
                return await turnOnDischarging(
                    chargerConnected: chargerConnected,
                    disableSleep: sleepIsDisabledForDischarge,
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
                // `await !systemDischargesToLimitItself()`: under Apple's charge limit macOS
                // performs this discharge itself, and the branch is keyed on the limit **in
                // force** rather than the one requested — so the system is draining to
                // exactly the value tested here, including when a sub-80 request was refused
                // and 80 is holding instead. Running `CHIE` alongside it duplicates a
                // discharge that is already happening, and `turnOnDischarging` is also what
                // takes the sleep assertion: the system's own drain continues while asleep
                // and lid-closed, so holding sleep off for it burns battery and heat to buy
                // nothing. Falls through to `inhibitCharging`, which is the honest mode —
                // charging is being held, just not by BatFi.
                if currentBatteryLevel > effectiveLimitInForce, allowDischarging, isLidOpenedOrSleepDisabled,
                   !computerIsAsleep, await !systemDischargesToLimitItself() {
                    await turnOnDischarging(
                        chargerConnected: chargerConnected,
                        disableSleep: sleepIsDisabledForDischarge,
                        currentMode: currentMode
                    )
                    return
                } else {
                    // `.inhibit` is the honest mode here — charge is being held — but on a
                    // mechanism that drains to the limit itself it is being held by macOS,
                    // which is also actively running the battery *down* to get there. The
                    // condition is the same one the discharge arm above steps aside for, so
                    // the two cannot both claim the battery is being discharged, and it is
                    // keyed on the limit **in force** rather than the one requested because
                    // that is the value the system drains to.
                    await inhibitCharging(
                        chargerConnected: chargerConnected,
                        currentMode: currentMode,
                        systemIsDischargingToLimit: SystemChargeDrain.isUnderway(
                            batteryLevel: currentBatteryLevel,
                            limitInForce: effectiveLimitInForce,
                            mechanismDrainsToLimitItself: await systemDischargesToLimitItself()
                        )
                    )
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
            } else if systemIsHoldingBelowLimit {
                // Below the limit and *still* not charging, with the firmware naming Apple's
                // own limit as the reason. `turnOnCharging` below would be the honest answer
                // on every backend BatFi drives with an inhibit of its own — there, below the
                // limit means the inhibit comes off and the firmware charges. Here it writes
                // nothing at all, and reports `.charging` for a battery at 0 mA: measured on
                // 26A5416b at 56% against a 60% limit, for two hours, while the menu read
                // "Charging to the limit".
                //
                // `.inhibit` is the honest mode for the same reason it is during the drain —
                // charge is being held, just not by BatFi — and this arm sits below the sleep
                // one so that an inhibit BatFi genuinely asked for keeps its own label.
                return await inhibitCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode,
                    systemIsHoldingBelowLimit: true
                )
            } else {
                return await turnOnCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            }
        }
    }

    /// Gets a charge session macOS closed re-opened, once a hold has lasted long enough to be
    /// worth writing to the user's own charge limit over.
    ///
    /// Separate from `checkForChargeHoldDrift` because it is a different fault with a different
    /// remedy: drift is the limit failing to hold and is answered by re-asserting it, which was
    /// measured *not* to help here. This is the limit holding immaculately while the charger
    /// stays off, and the only thing that answers it is changing the enforced value.
    private func checkForChargeResumeStall(isHolding: Bool, target: Int, now: Date) async {
        guard nudgeMonitor.record(isHolding: isHolding, at: now) == .nudge else { return }
        guard let nudgeValue = ChargeResumeNudge.target(forLimitInForce: target) else {
            logger.notice("Charge is held below a \(target, privacy: .public)% limit but there is no room to nudge above it")
            return
        }
        logger.notice("Charge has been held below the limit for \(Int(ChargeResumeNudgeMonitor.nudgeAfter), privacy: .public)s; nudging the limit to \(nudgeValue, privacy: .public)% to re-open the charge session")
        await analytics.addBreadcrumb(
            category: .chargingManager,
            message: "Nudging charge limit to \(nudgeValue)% to resume charging below a \(target)% limit"
        )
        do {
            let nudged = try await chargingClient.nudgeChargeLimit(nudgeValue, target)
            if nudged {
                // The helper moved the limit twice, so nothing this process recorded about the
                // hardware is still trustworthy.
                hardwareStateMayBeStale = true
            }
        } catch {
            logger.error("Charge-resume nudge failed: \(error, privacy: .public)")
        }
    }

    /// Whether macOS is holding charge on a battery that sits below the limit.
    ///
    /// The backend question is asked first and on its own, so that `holdAttribution` — an XPC
    /// round trip that opens the SMC — is never reached on a mechanism BatFi drives itself,
    /// where this state cannot arise and a battery below the limit that is not charging is
    /// `ChargeHoldDrift`'s question instead.
    private func systemIsHoldingChargeBelowLimit(
        powerState: PowerState,
        chargerConnected: Bool,
        limitInForce: Int,
        currentMode: ChargingMode
    ) async -> Bool {
        guard await systemDischargesToLimitItself() else { return false }
        let holdIsAttributed = await holdAttribution(
            chargerConnected: chargerConnected,
            isCharging: powerState.isCharging,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            now: date.now
        )
        // Asked only where the IOKit answer would otherwise be "held", which bounds this XPC
        // round trip to a state that is by definition idle. Everywhere else it stays nil and
        // the rule falls back to IOKit, as it did before.
        let iokitSaysHeld = SystemChargeHold.isHoldingBelowLimit(
            chargerConnected: chargerConnected,
            isCharging: powerState.isCharging,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            holdIsAttributed: holdIsAttributed,
            chargeIsFlowingIn: nil,
            batFiIsDischarging: currentMode == .forceDischarge,
            mechanismOwnsChargingDecision: true
        )
        var chargeIsFlowingIn: Bool?
        if iokitSaysHeld {
            // `batteryPower < 0` is the battery as a *target* rather than a source — the sign
            // convention `PowerGraph` renders. A helper that cannot answer leaves this nil, so
            // an unreachable helper cannot turn a hold into a phantom charge.
            chargeIsFlowingIn = (try? await powerDistributionClient.powerInfo()).map { $0.batteryPower < 0 }
        }
        let isHolding = SystemChargeHold.isHoldingBelowLimit(
            chargerConnected: chargerConnected,
            isCharging: powerState.isCharging,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            holdIsAttributed: holdIsAttributed,
            chargeIsFlowingIn: chargeIsFlowingIn,
            batFiIsDischarging: currentMode == .forceDischarge,
            mechanismOwnsChargingDecision: true
        )
        // Logged on the transition only, and compared against the *published* flag rather
        // than a private copy: every other path clears that flag through
        // `setSystemChargeHold`, so it cannot go stale here and claim a fresh entry into a
        // state the app has been in for an hour — or miss a genuine re-entry.
        //
        // A log and a breadcrumb rather than a notification. There is nothing to tell the
        // user to do yet: re-writing the same limit does not re-open the charge session
        // macOS closed, so a warning here would name a fault BatFi cannot act on. What it
        // buys is the state being legible in a support log at all, which is what two hours
        // of "Handling enable charge → no SMC write needed" was not.
        let wasHolding = await appChargingState.currentAppChargingMode().systemIsHoldingBelowLimit
        if isHolding, !wasHolding {
            logger.error("macOS is holding charge below the limit: battery \(powerState.batteryLevel, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, firmware attributes the hold to its own limit. BatFi has no write that can resume charging.")
            await analytics.addBreadcrumb(
                category: .chargingManager,
                message: "System is holding charge at \(powerState.batteryLevel)% below a \(limitInForce)% limit"
            )
        } else if !isHolding, wasHolding {
            logger.notice("macOS is no longer holding charge below the limit; battery \(powerState.batteryLevel, privacy: .public)%, charging \(powerState.isCharging, privacy: .public)")
        }
        return isHolding
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
        // BatFi is handing charging back and releasing the limit it applied, so there is no
        // BatFi limit left for the system to drain to. Whatever the user's own System
        // Settings limit then does is not something this app may narrate.
        await appChargingState.setSystemChargeHold(false, false)
        // BatFi is handing charging back, so the next limit it applies starts a new
        // episode and is worth reporting again even if it resolves — or fails — the same way.
        lastReportedChargeLimit = nil
        lastReportedChargeLimitFailure = nil
        // Handing charging back puts the hardware somewhere BatFi did not choose, so the
        // next command it does issue must not be skipped as already in force.
        invalidateHardwareState()
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
            await setSleepDisabled(false)
        }
        // BatFi is handing charging back, so it must not still be preventing automatic
        // sleep. The license-invalid guard in `updateStatus` returns through here *before*
        // reaching `setUpDelaySleep`, so without this a held prevent-automatic-sleep
        // assertion survived until quit.
        await restoreSleepifNeeded()
        await appChargingState.updateChargingMode(.charging)
    }

    /// Whether a charging command has to be sent, or whether the hardware is already known
    /// to be holding it.
    ///
    /// `currentMode` is what the app believes the hardware was last told, and it is only
    /// advanced by an applier that succeeded — a throw leaves it where it was, so a failed
    /// command is retried by the next update rather than assumed to have landed.
    ///
    /// The staleness flag is what keeps this from being a one-way latch. Sleep, a wake, a
    /// helper that went away and came back, the charger being plugged or unplugged: each is
    /// a moment when the SMC can be holding something BatFi did not put there, and each
    /// clears the flag's assumption so the next command goes out no matter what the mode
    /// says.
    private func shouldApply(_ target: ChargingMode, currentMode: ChargingMode) -> Bool {
        if hardwareStateMayBeStale || currentMode != target { return true }
        guard let lastAppliedAt else { return true }
        return date.now.timeIntervalSince(lastAppliedAt) >= Self.reassertionInterval
    }

    /// Called once a command has actually reached the hardware.
    private func didApply() {
        hardwareStateMayBeStale = false
        lastAppliedAt = date.now
    }

    /// Called when something may have changed the hardware behind the app's back, so the
    /// next command is sent whether or not the app thinks it is already in force.
    private func invalidateHardwareState() {
        hardwareStateMayBeStale = true
    }

    /// Whether a discharge-related sleep assertion could be outstanding.
    ///
    /// The release sites used to be gated on `allowDischargingFullBattery` alone, so
    /// turning that off mid-discharge stranded the assertion with nothing left that would
    /// release it. Both settings that can *take* one are named here, so neither can be
    /// switched off out from under its own release. Still gated rather than unconditional:
    /// `disableSleep(false)` makes an XPC call, and this runs on every status update.
    private var sleepAssertionMayBeHeldForDischarging: Bool {
        sleepWasDisabledForDischarging
            || defaults.value(.allowDischargingFullBattery)
            || defaults.value(.disableSleepDuringDischarging)
    }

    /// Whether BatFi currently has sleep disabled for a discharge.
    ///
    /// Naming the settings above is no longer enough to know that: a manual discharge on a
    /// mechanism that drains to the limit itself disables sleep with **neither** of them on, so
    /// the guard would skip the release and leave the Mac unable to sleep after the discharge
    /// ended. Recording the fact beats enumerating the causes, which is the trap the comment
    /// above already describes — every future taker is covered without being listed.
    private var sleepWasDisabledForDischarging = false

    /// The single writer, so the flag cannot drift from what was actually asked for.
    private func setSleepDisabled(_ disabled: Bool) async {
        try? await sleepAssertionClient.disableSleep(disabled)
        sleepWasDisabledForDischarging = disabled
    }

    /// Whether a discharge on this Mac would be BatFi's own SMC discharge on a mechanism that
    /// otherwise drains to the limit itself — the one case that disables sleep outright.
    /// Read by the app layer to decide whether the disclosure alert is owed.
    public func manualDischargeDisablesSleep() async -> Bool {
        await systemDischargesToLimitItself()
    }

    private func turnOnCharging(chargerConnected: Bool, currentMode: ChargingMode) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        // Charging, so nothing is draining. Cleared here rather than only where it is set,
        // and above the guard for the same reason it is set above one: this pass may skip
        // the command as already in force, and a stale "Discharging to the limit" outliving
        // the drain is the failure the flag exists to prevent.
        await appChargingState.setSystemChargeHold(false, false)
        guard shouldApply(.charging, currentMode: currentMode) else { return }
        logger.debug("Turning on charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on charging")
        do {
            try await chargingClient.turnOnAutoChargingMode()
            if sleepAssertionMayBeHeldForDischarging {
                await setSleepDisabled(false)
            }
            await analytics.addBreadcrumb(category: .chargingManager, message: "Charging turned on")
            didApply()
            await appChargingState.updateChargingMode(.charging)
        } catch {
            logger.warning("Failed to turn on charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on charging. Error: \(error.localizedDescription)")
        }
    }

    /// - Parameters:
    ///   - systemIsDischargingToLimit: whether macOS is draining the battery down to the
    ///     limit on its own right now.
    ///   - systemIsHoldingBelowLimit: whether macOS is holding charge on a battery already
    ///     below the limit — the charge session closed and not re-opened.
    ///
    ///   Both default to `false` because every caller but one is
    ///   on a path where BatFi genuinely holds the inhibit: the two backend-gated sleep
    ///   hooks and the hot-battery cutout all check `backendCanPauseChargingOnDemand()`
    ///   first, and the override arms are labelled by the override rather than by the mode.
    ///   Only the no-override arm of `updateStatus` can reach `.inhibit` *because* the
    ///   system is draining, and it is the only site that answers this.
    private func inhibitCharging(
        chargerConnected: Bool,
        currentMode: ChargingMode,
        systemIsDischargingToLimit: Bool = false,
        systemIsHoldingBelowLimit: Bool = false
    ) async {
        await updateChargerConnected(chargerConnected)
        // Beside `updateChargerConnected` and above the guard, deliberately. This reports
        // what is true right now rather than what BatFi just wrote, and it goes on changing
        // while the mode does not: a 61% battery draining to a 55% limit is `.inhibit` for
        // the whole descent and `.inhibit` again when it settles. Below the guard it would
        // only ever be refreshed on the passes that actually send a command, so the label
        // would latch at whichever value was true when the mode last changed.
        await appChargingState.setSystemChargeHold(
            systemIsDischargingToLimit,
            systemIsHoldingBelowLimit
        )
        guard shouldApply(.inhibit, currentMode: currentMode) else {
            // Already inhibiting and nothing has happened that could have undone it. The
            // pulling task is not restarted here: it was started when this mode was entered
            // and is still running.
            return
        }
        logger.debug("Inhibiting charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibiting charging")
        do {
            try await chargingClient.inhibitCharging()
            if sleepAssertionMayBeHeldForDischarging {
                await setSleepDisabled(false)
            }
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging turned on")
            didApply()
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
        // BatFi's own discharge, which `.forceDischarge` already names. The system's drain
        // and this one are mutually exclusive by construction — `updateStatus` skips its
        // discharge arm entirely on a mechanism that drains itself — so this can only ever
        // be clearing a value left by an earlier pass.
        await appChargingState.setSystemChargeHold(false, false)
        // Ahead of the assertion, not after it. Taking the assertion first and then
        // returning through this guard stranded it: nothing below runs, and every release
        // site is on a path this pass no longer reaches.
        guard chargerConnected else {
            logger.debug("Charger not connected, skipping discharging")
            // Restoring sleep here is right when the charger is genuinely gone and wrong when
            // it is gone *because of this discharge*. `CHIE` takes the adapter out of the
            // circuit, so `ExternalConnected` goes false within seconds of starting, and this
            // guard then undid the very disable the discharge needs: measured on 26A5416b,
            // "Restoring sleep" 13s after "Force discharge", and the Mac slept with the lid
            // closed mid-discharge.
            //
            // `disableSleep` is the caller stating that this discharge requires sleep off, and
            // `TempOverrideDisconnectPolicy` already reads an absent charger during a discharge
            // override as "the requested state, not a reason to drop it". The release still
            // happens when the discharge ends, through `sleepAssertionMayBeHeldForDischarging`.
            if !disableSleep {
                await setSleepDisabled(false)
            }
            return
        }
        await setSleepDisabled(disableSleep)
        if defaults.value(.disableSleepDuringDischarging) {
            await setSleepDisabled(true)
        }
        // Below the sleep assertions on purpose. Those follow `disableSleep`, which the user
        // can change while the discharge is already running, so they are not the mode's to
        // skip — only the charging command itself is.
        guard shouldApply(.forceDischarge, currentMode: currentMode) else { return }
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on discharging")
        logger.debug("Turning on discharging")
        do {
            try await chargingClient.forceDischarge()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Discharging turned on")
            didApply()
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
                    ),
                    // Stated rather than inherited: this is built from the *helper's* status
                    // read, which carries no answer about the drain, and the paths that
                    // reach it — a wake, a display change, the first mode of the session —
                    // are exactly the ones where an earlier answer should not be trusted.
                    // `updateStatusWithCurrentState()` on the next line re-derives it from
                    // the current battery level and limit.
                    systemIsDischargingToLimit: false,
                    systemIsHoldingBelowLimit: false
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

    /// The value last written to the log and the breadcrumb trail, which is not the same as
    /// the value last handed to `appChargingState` — that one is set on every pass because
    /// it is local and free, while these two are neither.
    private var lastLoggedChargerConnected: Bool?

    private func updateChargerConnected(_ chargerConnected: Bool) async {
        // On change, not on every pass, for the same reason the applied charge limit is
        // reported on change: this runs on every power-source notification. Unconditional,
        // it wrote 2,748 identical `notice` lines and 2,748 Sentry breadcrumbs in 2h20m on a
        // Mac that was sitting still — which is both a cost in itself and the reason a real
        // helper failure took as long as it did to find in the log afterwards.
        if lastLoggedChargerConnected != chargerConnected {
            lastLoggedChargerConnected = chargerConnected
            await analytics.addBreadcrumb(category: .chargingManager, message: "Updating charger connected status")
            logger.notice("Updating charger connected status: \(chargerConnected)")
        }
        await appChargingState.setChargerConnected(chargerConnected)
    }

    // MARK: - Last state of charger connected
    private func updateLastChargerConnectedStateIfNeeded(_ chargerConnected: Bool) {
        let newState = ChargerConnectedStatus(date: date.now, isConnected: chargerConnected)
        if let lastChargerConnectedStatus {
            if lastChargerConnectedStatus.isConnected != chargerConnected {
                logger.debug("Update last charger connected status: \(chargerConnected)")
                // Unplugging drops whatever the charge mechanism was holding, so the command
                // has to be re-sent when the charger comes back rather than assumed intact.
                invalidateHardwareState()
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
