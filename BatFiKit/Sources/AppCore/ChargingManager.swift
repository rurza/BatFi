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
    @Dependency(\.otherChargeTools) private var otherChargeTools

    /// The run of readings that contradict the hold BatFi's configuration implies.
    ///
    /// Everything else here re-issues commands on a schedule and believes what it wrote.
    /// This is the one thing that asks the battery, so that a limit retired underneath BatFi
    /// — by macOS, by another app taking the mechanism over, by firmware doing something
    /// nobody has characterised — is noticed rather than reported as applied forever.
    private var driftMonitor = ChargeHoldDriftMonitor()
    private var nudgeMonitor = ChargeResumeNudgeMonitor()
    /// Keeps the macOS top-up once it has genuinely begun, so the plateau at ~100% is not
    /// relabelled a drain by every outward burst of the SMC reading. See
    /// `SystemChargeTopUpLatch`; read and advanced only by `systemChargeAboveLimit`.
    private var topUpLatch = SystemChargeTopUpLatch()
    /// The firmware's last answer to "is anything holding charge right now", and when it was
    /// asked. Throttled because asking is an XPC round trip into
    /// `SMCService.chargingDiagnostics()`, which opens the SMC, reads `CHNC`, queries PowerUI
    /// and probes three more keys — on the same actor that serves `applyChargeLimit`.
    private var lastHoldAttribution: Bool?
    private var lastHoldAttributionAt: Date?
    /// powerd's enforced limit across passes, for the windows after a raise in which a
    /// battery about to charge looks held below the limit. See `ChargeLimitRaiseWindow`.
    private var limitRaiseWindow = ChargeLimitRaiseWindow()

    private var computerIsAsleep = false
    private lazy var logger = Logger(category: "Charging Manager")

    private var powerStatePullingTask: Task<Void, Never>?
    /// Whether `setUpObserving()` has already run. See there.
    private var isObserving = false
    private var unlockModel: UnlockModel?
    /// The licence, or a running trial, as charge management acts on it. Three states rather
    /// than `hasValidLicense`'s two — see `LicenseStatus.chargeManagement`.
    private var licenseStatus: LicenseStatus = .unknown

    private var lastChargerConnectedStatus: ChargerConnectedStatus?

    /// When the temp override now in force was armed, and what the battery read then.
    ///
    /// Both rules that *delete* an override ask whether something happened since the user
    /// asked for it — the charger has been out long enough, the battery reached full — and
    /// neither could tell that from the state the click landed in. So an override armed on
    /// battery was born past the disconnect deadline, and one armed against a full battery
    /// satisfied its own completion test, and both were deleted by the status pass that
    /// followed the click, about 100 ms later. Caught in a customer log 2026-08-31:
    /// "Charger disconnected long enough, removing temp override" 184 ms before the charger
    /// read connected again.
    ///
    /// Kept here rather than on `UserTempChargingMode`, which is a value the whole app
    /// compares for equality and posts through notifications; this is bookkeeping for the
    /// two rules below and nothing else reads it.
    private var tempOverrideArm: TempOverrideArm?

    /// Whether the battery is being kept at 100% because a "Charge to 100%" got it there and
    /// the charger has not come out since.
    ///
    /// Not carried on the override, because the override is gone by the time this begins —
    /// `ChargeToFullCompletion` retires it at 100% and that is exactly the moment this starts.
    /// That gap is the bug, from a customer log of 2026-09-22: the limit snapped back to 70%,
    /// the next pass read 100% against a 70–75% band with "Discharge battery when overcharged"
    /// on, and BatFi force-discharged for twenty minutes the 30% the user had just asked it to
    /// put in.
    ///
    /// Plain in-memory state rather than a preference: a relaunch drops the hold and the
    /// battery goes back to the user's limit, which is accepted for now. Restoring it would
    /// mean persisting an intent whose end condition — the next unplug — cannot be checked
    /// against anything a restarted process knows about the one before it.
    ///
    /// Read by `ChargeToFullHold`, which owns the transitions.
    private var holdingFullChargeUntilUnplugged = false

    /// The charge limit a hot battery is being held at on `.systemChargeLimit`, or nil.
    ///
    /// That backend has no inhibit, so "turn off charging when the battery is hot" is a limit
    /// set to the level the battery reached, frozen until it cools — see `HotBatteryHold`,
    /// which owns the transitions. Substituted into the requested limit, so everything
    /// downstream of `applyChargeLimit` sees it as the limit in force.
    ///
    /// **In memory only, and that is the restore path.** It is never written to
    /// `Defaults[.chargeLimit]` or any other key, so nothing outlives the process: if the app
    /// dies mid-episode the helper's exit watcher restores system defaults, and the next
    /// launch applies the user's own limit — and freezes afresh if the battery is still hot.
    /// Cleared in `disengage()` so charge management coming back on never applies a value
    /// frozen before it went off.
    private var hotBatteryHoldLimit: Int?

    /// Sailing's phase, carried from pass to pass — see `SailingPhaseTracker`. Advanced only by
    /// `advanceSailing`; forgotten on wake, on handing charging back, and with charge
    /// management off. In memory only: a relaunch starts afresh, which is a fresh start's rule.
    private var sailingTracker = SailingPhaseTracker()

    /// The limit sailing keeps in force while it holds where macOS enforces the limit
    /// (`.systemChargeLimit`) — see `SailingLimitHold`. Reset when charging is handed back, so
    /// charge management coming back on never keeps a value frozen before it went off. Kept
    /// across a wake: a phase that starts afresh holding goes on holding with the value already
    /// in force, because writing a new one would start a charge.
    private var sailingLimitHold = SailingLimitHold()

    /// Whether the sailing hold kept a value other than the person's limit on the last pass,
    /// so its start and end are logged once and reset the drift and nudge monitors.
    private var sailingFreezeWasInForce = false

    /// What the helper was last told about the firmware's band, as the client reports it: the
    /// band down to a resume level, or the one-value call in its place. Only a band that went
    /// out is measured and named — see `FirmwareBandHandover`.
    private var firmwareBandHandover = FirmwareBandHandover()

    /// The band sailing holds with under `.firmwareRange` when its hold began below the limit:
    /// the upper bound at the battery's level, the lower at the resume level — see
    /// `FirmwareSailingHold`. Reset when charging is handed back.
    private var firmwareSailingHold = FirmwareSailingHold()

    /// The held band last asked for, so each write and release is logged once.
    private var lastFirmwareSailingBand: FirmwareSailingHold.Band?

    /// Whether sailing was last left to the firmware under `.firmwareRange`, so the change is
    /// logged once.
    private var firmwareSailingIsLeftToTheFirmware = false

    /// The resume level of the band last handed to the firmware, so its change is logged once
    /// rather than per pass. Nil with sailing off, on any other backend, and while the helper
    /// was given the one-value call instead.
    private var lastFirmwareBandResumeLevel: Int?

    /// The override last left out of the band's limit (`FirmwareRangeDischarge`), so the
    /// change is logged once rather than per pass.
    private var overrideLeftOutOfFirmwareBand: UserTempChargingMode?

    /// The floor this Mac's charge mechanism has been seen to apply a sub-80 request at — 80
    /// where macOS has no path below it — or nil where none was seen
    /// (`ChargingAheadOfApply.learnedFloor`). What a request is judged at before its apply.
    private var applyFloor: Int?

    /// The run of failed SMC inhibit writes for the pause in force, on the backends that pause
    /// on demand. See `InhibitWriteFailures`.
    private var inhibitWriteFailures = InhibitWriteFailures()

    /// Keeps "Resume Discharging" shown as macOS draining while powerd adopts the lowered
    /// limit — see `DischargeResumeHold`.
    private var dischargeResumeHold = DischargeResumeHold()

    /// Whether the last pass found a manual inhibit held by freezing Apple's limit — only so
    /// its start and end are each said once and reset the monitors. The hold itself is the
    /// override, which lives in `appChargingState` and, like everything there, in memory
    /// only: a relaunch starts without it and applies the user's own limit. See
    /// `ManualInhibit`.
    private var manualInhibitWasHeld = false

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
    /// nothing anywhere says so: the Charging pane toggle still reads ON, the battery info
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
        bandResumeLevel: Int?,
        limitInForce: Int,
        currentMode: ChargingMode,
        systemIsChargingPastLimit: Bool,
        systemIsDrainingToLimit: Bool,
        systemTopUpIsLatched: Bool,
        frozenLimitIsInForce: Bool
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
            holdIsAttributed: holdIsAttributed,
            systemIsChargingPastLimit: systemIsChargingPastLimit,
            systemIsDrainingToLimit: systemIsDrainingToLimit
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
        // What the last scan found, never a new scan: this runs once a minute for as long as
        // the fault lasts. The tool is the likeliest cause a report can name.
        let installedTools = await otherChargeTools.latest()
        let otherTools = installedTools.map { $0.isEmpty ? "none" : $0.map(\.description).joined(separator: ", ") } ?? "not scanned yet"
        logger.error("Charge limit is not holding: battery \(powerState.batteryLevel, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, charging \(powerState.isCharging, privacy: .public), firmware attributes a hold: \(attribution, privacy: .public), other charge-control tools: \(otherTools, privacy: .public). Reasserting \(requestedLimit, privacy: .public)%")
        await analytics.addBreadcrumb(
            category: .chargingManager,
            message: "Charge limit not holding at \(powerState.batteryLevel)% against \(limitInForce)%; other charge-control tools: \(otherTools); reasserting"
        )
        // Whatever took the limit may have taken the SMC mode with it, so the next applier
        // re-issues its command too rather than trusting what it last wrote.
        hardwareStateMayBeStale = true
        // The reassert carries the limit alone, and the helper re-arms the band with the
        // resume level it was last asked for. This pass's apply has normally just told it;
        // telling it again first covers a helper that restarted since, which would otherwise
        // re-arm today's narrower band and have the next pass widen it again. On an unchanged
        // helper the range call writes nothing. Only for a band that was handed over, and in
        // its own `do`, so a range call that fails still leaves the reassert to run.
        if let bandResumeLevel {
            do {
                let range = try await chargingClient.applyChargeRange(requestedLimit, bandResumeLevel)
                firmwareBandHandover.record(limit: requestedLimit, resumeLevel: bandResumeLevel, call: range.call)
            } catch {
                logger.error("Handing the firmware its band before reasserting \(requestedLimit, privacy: .public)% failed: \(error, privacy: .public)")
            }
        }
        do {
            let applied = try await chargingClient.reassertChargeLimit(requestedLimit)
            logger.notice("Charge limit reasserted; \(applied, privacy: .public)% now in force")
        } catch {
            logger.error("Reasserting charge limit \(requestedLimit, privacy: .public)% failed: \(error, privacy: .public)")
        }

        if response == .warnTheUser {
            // The menu is saying macOS is calibrating the battery, which is what this would look
            // like; the re-apply above still ran. The run's one warning is spent either way.
            guard !systemTopUpIsLatched else {
                logger.notice("Not warning that the charge limit is not holding; macOS is charging past it for calibration")
                return
            }
            // A frozen limit — a hot battery's, or a manual inhibit's on Apple's charge limit
            // — is BatFi's own short-lived value, and the notification would hand it to the
            // user as theirs — "BatFi re-applied your 63% limit", a number they never set. The
            // reassert above still ran, with the frozen value, which is what keeps it
            // coherent: the run is about the limit in force.
            guard !frozenLimitIsInForce else {
                logger.notice("Not warning that the charge limit is not holding; it is a temporary frozen limit")
                return
            }
            await warnThatTheChargeLimitIsNotHolding(limit: requestedLimit, installedTools: installedTools)
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

    /// Tells the user, once per run, that the limit they set is not being honoured — and,
    /// when another tool that can write the limit is installed, which one and how to remove
    /// it. See `ChargeLimitNotHoldingWarning`.
    ///
    /// `installedTools` is the last scan's result. Only when there is none yet — the scan at
    /// launch has not finished — is one run here; this is the once-per-run path, so it costs
    /// one scan at most.
    private func warnThatTheChargeLimitIsNotHolding(limit: Int, installedTools: [DetectedChargeTool]?) async {
        guard await userNotificationsClient.requestAuthorization() == true else { return }
        let percentage = percentageFormatter.string(from: NSNumber(value: Double(limit) / 100)) ?? "\(limit)%"
        let detected: [DetectedChargeTool]
        if let installedTools {
            detected = installedTools
        } else {
            detected = await otherChargeTools.detect()
        }
        let warning = ChargeLimitNotHoldingWarning(
            limit: percentage,
            detected: detected,
            backend: await chargeBackend(),
            markingCommand: { ChargeLimitNotHoldingWarning.quotingCommand($0) }
        )
        if let suspect = warning.suspect {
            logger.notice("Warning that the charge limit is not holding, naming \(suspect.description, privacy: .public)")
        } else {
            logger.notice("Warning that the charge limit is not holding; no other charge-control tool to name")
        }
        do {
            try await userNotificationsClient.showUserNotification(
                title: warning.title,
                body: warning.body,
                identifier: "software.micropixels.BatFi.notifications.chargeLimitNotHolding",
                threadIdentifier: "Charge limit",
                delay: nil
            )
        } catch {
            logger.error("Could not post the charge-limit warning: \(error, privacy: .public)")
        }
    }

    public func setUpObserving() {
        // Called once, whatever the caller does.
        //
        // Every `Task` below runs for the life of the process and none was retained, so a
        // second call did not replace the observers — it *added* a set. `setUpTheApp()` calls
        // this from two places (launch, and the onboarding completion handler), and each extra
        // main loop is another `updateStatus` driving the same state concurrently. `actor`
        // does not save it: `updateStatus` awaits throughout, and actors are reentrant, so the
        // passes interleave rather than queue. Measured 2026-08-26 — the top-up transition,
        // which by construction can only be logged once per entry, logged twice in the same
        // second, each pass having read the flag before either wrote it.
        guard !isObserving else {
            logger.notice("setUpObserving() called again; the observers are already running")
            return
        }
        isObserving = true
        assert(unlockModel != nil)
        observeHelperHealth()
        // Not awaited: it costs an XPC round trip, and nothing below depends on its answer
        // — a pass that runs first simply declines to release a flag it does not yet know
        // is BatFi's, and the next one releases it.
        Task { await adoptSleepDisableLeftByAnEarlierVersionIfNeeded() }
        Task {
            for await (
                (
                    (userTempChargingMode, powerState)
                ),
                (
                    (inhibitOnSleep, disableSleepDuringDischarge),
                    (preventAutomaticSleep, temperature),
                    (chargeLimit, manageCharging, allowDischarging)
                ),
                (sailingEnabled, sailingResumeLevel)
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
                ),
                combineLatest(
                    defaults.observe(.sailingEnabled),
                    defaults.observe(.sailingResumeLevel)
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
                    disableSleepDuringDischarge: disableSleepDuringDischarge,
                    sailingEnabled: sailingEnabled,
                    sailingResumeLevel: sailingResumeLevel
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
                    // The battery may have crossed either level while BatFi could decide
                    // nothing, so the phase starts afresh from the charge it woke at. Where
                    // macOS enforces the limit a hold that goes on keeps the value in force
                    // (`sailingLimitHold`); one that ends releases it on the next pass.
                    forgetSailingPhase(because: "the Mac woke")
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
            for await status in await unlockModel!.statusChanges() {
                licenseStatus = status
                await updateStatusWithCurrentState()
            }
        }

        Task {
            // The limit and the rule's resume level alike: a rule edited or taking over during a
            // sailing hold goes through the same pass as a slider move.
            for await _ in appChargingState.automationTargetDidChange() {
                logger.debug("Automation target changed, re-evaluating charging")
                await updateStatusWithCurrentState()
            }
        }
    }

    public func setUnlockModel(_ unlockModel: UnlockModel) {
        self.unlockModel = unlockModel
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

    /// Where the menu item and the `.inhibitCharging` hotkey converge, so the gate lives here,
    /// below both. The menu already withholds the command where it cannot work
    /// (`StatusMenuCommands`), but a shortcut the user bound earlier still fires — and is
    /// deliberately left bound, so it comes back on a Mac that can hold charge.
    nonisolated public func inhibitCharging() {
        Task { await inhibitChargingAtCurrentLevel() }
    }

    private func inhibitChargingAtCurrentLevel() async {
        // An override at the battery's level, on every backend that can hold one — and its
        // end is the override's own: Stop Override, another override replacing it, or the
        // charger staying out (`TempOverrideDisconnectPolicy`). Under `.systemChargeLimit`
        // there is no inhibit to hold it with, so the override is held by freezing Apple's
        // limit at that level instead (`ManualInhibit`); `updateStatus` exempts it from the
        // reached-target retirement that used to end it after one pass. Under
        // `.firmwareRange` a band at the current level lets the battery fall five points and
        // charges it back, which is no pause. Ignored there silently, as the menu would be,
        // but logged so a customer log says why the key did nothing.
        //
        // Charging is paused as charging; a battery discharging on the charger — macOS
        // draining it to the limit, or BatFi's own discharge — as "Pause Discharging", the same
        // override marked as pausing a discharge (`ManualInhibit.pause`). The menu and the
        // hotkey ask the same rule, so the key does nothing where the menu offers nothing:
        // off the charger, while a pause is armed, or while charge is merely held.
        let backend = await chargeBackend()
        guard ManualInhibit.isAvailable(on: backend) else {
            logger.notice("Inhibit charging ignored: this Mac's charge mechanism (\(backend?.rawValue ?? "unknown", privacy: .public)) cannot hold charge at its current level")
            return
        }
        guard let powerState = try? await powerSourceClient.currentPowerSourceState() else { return }
        // Judged against this click's own readings: a pause that would not hold — under the
        // floor of a Mac whose limit cannot go below 80, or a discharge pause that rounds to the
        // limit the discharge is heading to — arms nothing (`ManualInhibit.holds`).
        let published = await appChargingState.currentAppChargingMode()
        let context = await pauseHoldContext(overrideInForce: published.userTempOverride)
        guard let pause = ManualInhibit.pause(for: published, batteryLevel: powerState.batteryLevel, backend: backend, context: context) else {
            logger.notice("Pause ignored: nothing to pause in mode \(published.mode.rawValue, privacy: .public) (charger connected \(published.chargerConnected, privacy: .public), macOS draining \(published.systemIsDischargingToLimit, privacy: .public), pause armed \(published.userTempOverride?.isInhibit == true, privacy: .public))")
            return
        }
        if pause.pausesDischarge {
            logger.notice("Pause discharging at \(pause.limit, privacy: .public)% with the battery at \(powerState.batteryLevel, privacy: .public)%\(pause.resumesOverrideLimit.map { "; resuming restores the \($0)% override" } ?? "", privacy: .public)")
        }
        await appChargingState.setTempOverride(pause)
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

    /// Stop Override — the hotkey, Shortcuts — ends with no override in force, a paused
    /// discharge included: automations rely on it.
    nonisolated public func stopOverride() {
        Task { await endOverride(restoringPausedOverride: false) }
    }

    /// "Resume Charging" / "Resume Discharging" in the menu: as Stop Override, except that a
    /// discharge pause puts back the discharge it replaced.
    nonisolated public func resumePause() {
        Task { await endOverride(restoringPausedOverride: true) }
    }

    /// Ends the override in force, publishing in the same breath the state the pass after the
    /// click will decide — `ChargingAheadOfApply.onEndingOverride` — so the `.inhibit` left over
    /// from a pause is never shown on its own. The command for it is the pass's to send: the
    /// hardware state is marked stale so that pass sends it whatever the published mode says.
    private func endOverride(restoringPausedOverride: Bool) async {
        guard let ending = await appChargingState.currentUserTempOverrideMode() else {
            await appChargingState.setTempOverride(nil)
            return
        }
        let powerState = try? await powerSourceClient.currentPowerSourceState()
        let backend = await chargeBackend()
        let resumedLimit = await resumedLimit()
        let published = await appChargingState.currentAppChargingMode()
        // "Resume Discharging" puts back the discharge it paused: the override it replaced, or
        // macOS draining to the limit again — published at the click either way, and the drain
        // held while powerd adopts the lowered limit (`DischargeResumeHold`). Judged by what
        // the pass after the click reads, at the limit the apply will put in force.
        let end: OverrideEnd
        if let powerState {
            let isLidOpened: Bool
            if let lidOpened = await appChargingState.lidOpened() {
                isLidOpened = lidOpened
            } else {
                isLidOpened = await fetchLidStatus()
            }
            let batteryIsHot: Bool
            if case .tooHot = HotBatteryProtection.decision(
                isEnabled: defaults.value(.temperatureSwitch),
                temperature: powerState.batteryTemperature,
                threshold: Constant.batteryTemperatureWarning
            ) {
                batteryIsHot = true
            } else {
                batteryIsHot = false
            }
            // Only for "Resume Discharging" with an override to put back; nil otherwise, so
            // with sailing off, and for every other end, nothing more is read.
            var restoredSailingResumeLevel: Int?
            if restoringPausedOverride, let restored = ending.overrideToResume {
                restoredSailingResumeLevel = await sailingResumeLevelAfterOverride(
                    backend: backend,
                    batteryLevel: powerState.batteryLevel,
                    resuming: restored
                )
            }
            end = ChargingAheadOfApply.onEndingOverride(
                ending,
                restoringPausedOverride: restoringPausedOverride,
                conditions: ResumeConditions(
                    backend: backend,
                    chargerConnected: published.chargerConnected,
                    batteryLevel: powerState.batteryLevel,
                    resumedLimit: resumedLimit,
                    floor: applyFloor,
                    appliesAreFailing: lastReportedChargeLimitFailure != nil,
                    isManagingCharging: defaults.value(.manageCharging) && licenseStatus.chargeManagement == .manage,
                    allowDischarging: defaults.value(.allowDischargingFullBattery),
                    lidOpenOrSleepDisabled: isLidOpened || defaults.value(.disableSleepDuringDischarging),
                    computerIsAsleep: computerIsAsleep,
                    batteryIsHot: batteryIsHot,
                    sailingResumeLevel: await sailingResumeLevelAfterOverride(backend: backend, batteryLevel: powerState.batteryLevel),
                    restoredSailingResumeLevel: restoredSailingResumeLevel
                )
            )
        } else {
            end = OverrideEnd(restoring: restoringPausedOverride ? ending.overrideToResume : nil)
        }
        if end.mode != nil {
            invalidateHardwareState()
        }
        if end.systemIsDischargingToLimit == true {
            dischargeResumeHold.arm()
        }
        if ending.pausesDischarge {
            logger.notice("Resume discharging from \(ending.limit, privacy: .public)%\(end.restoring.map { ": restoring the \($0.limit)% override" } ?? "", privacy: .public)\(end.mode.map { ", shown as \($0.rawValue)" } ?? "", privacy: .public)\(end.systemIsDischargingToLimit == true ? " with macOS draining" : "", privacy: .public)")
        }
        // The menu rebuilt for the end judges a pause against the discharge it resumes, not the
        // pause's frozen limit, which powerd goes on enforcing for up to 45 s: a quick re-pause
        // is offered.
        await appChargingState.setPauseContext(await pauseHoldContext(overrideInForce: end.restoring))
        // Only the override being ended: one armed meanwhile stays.
        await appChargingState.endOverride(ending, end)
    }

    /// The limit a pass requests with no override, by the rule `updateStatus` uses: the lower
    /// of a hot battery's frozen value and the user's limit — or an automation's, or the
    /// charge-to-full hold's.
    private func resumedLimit() async -> Int {
        let automationLimit = await appChargingState.currentAutomationTarget()?.limit
        return HotBatteryHold.requestedLimit(
            frozenAt: hotBatteryHoldLimit,
            otherwise: ChargeToFullHold.requestedLimit(
                holding: holdingFullChargeUntilUnplugged,
                otherwise: automationLimit ?? Int(defaults.value(.chargeLimit))
            )
        )
    }

    /// The resume level the pass after an override ends would sail to, or nil where it would
    /// not sail: the levels `advanceSailing` would put in play with no override in force. The
    /// phase after an override is a fresh start, which `onEndingOverride` applies.
    ///
    /// Where macOS enforces the limit the levels are judged where macOS enforces it, and
    /// a hold this Mac cannot express is none: the pass charges to the limit first.
    ///
    /// With `restored`, the levels of the override "Resume Discharging" puts back instead: a
    /// temporary limit sails by the main screen's switch and distance, and the pass after the
    /// click starts a fresh phase against it (the pause in force before it had no levels).
    /// Without it, an active rule's own levels count, as they do in `advanceSailing`.
    private func sailingResumeLevelAfterOverride(
        backend: ChargeBackend?,
        batteryLevel: Int,
        resuming restored: UserTempChargingMode? = nil
    ) async -> Int? {
        let sailingEnabled = defaults.value(.sailingEnabled)
        let automation = restored == nil ? await appChargingState.currentAutomationTarget() : nil
        let macOSEnforcesTheLimit = backend == .systemChargeLimit
        guard SailingRange.switchIsOn(mainSwitch: sailingEnabled, automation: automation, overrideInForce: restored),
              backend?.canPauseChargingOnDemand == true || macOSEnforcesTheLimit else { return nil }
        let chargeLimit = defaults.value(.chargeLimit)
        let targetLimit: Int
        if let restored {
            targetLimit = restored.limit
        } else {
            targetLimit = ChargeToFullHold.requestedLimit(
                holding: holdingFullChargeUntilUnplugged,
                otherwise: automation?.limit ?? chargeLimit
            )
        }
        if SailingLimitHold().cannotHoldOnEntry(
            phase: .holding,
            backend: backend,
            batteryLevel: batteryLevel,
            limitInForce: limitRaiseWindow.lastAppliedLimit,
            otherwise: targetLimit,
            floor: applyFloor
        ) {
            return nil
        }
        return SailingRange.levelsInPlay(
            enabled: sailingEnabled,
            targetLimit: macOSEnforcesTheLimit
                ? SailingLimitHold.limitMacOSEnforces(requested: targetLimit, floor: applyFloor)
                : targetLimit,
            configuredLimit: ChargeLimitRange.displayedLimit(configured: chargeLimit, for: backend),
            configuredResume: defaults.value(.sailingResumeLevel),
            automation: automation,
            overrideInForce: restored,
            holdingFullChargeUntilUnplugged: holdingFullChargeUntilUnplugged
        )?.resumeLevel
    }

    /// What a pause armed now is judged against, with `overrideInForce` in force.
    private func pauseHoldContext(overrideInForce: UserTempChargingMode?) async -> PauseHoldContext {
        PauseHoldContext(
            dischargeTarget: ManualInhibit.dischargeTarget(
                overrideInForce: overrideInForce,
                resumedLimit: await resumedLimit(),
                floor: applyFloor
            ),
            floor: applyFloor
        )
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
            let sailingEnabled = defaults.value(.sailingEnabled)
            let sailingResumeLevel = defaults.value(.sailingResumeLevel)

            await updateStatus(
                powerState: powerState,
                userTempChargingMode: userTempChargingMode,
                chargeLimit: Int(chargeLimit),
                manageCharging: manageCharging,
                allowDischarging: allowDischargingFullBattery,
                preventAutomaticSleep: preventAutomaticSleep,
                turnOffChargingWithHotBattery: batteryTemperature,
                inhibitChargingOnSleep: inhibitChargingOnSleep,
                disableSleepDuringDischarge: disableSleepDuringDischarge,
                sailingEnabled: sailingEnabled,
                sailingResumeLevel: sailingResumeLevel
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
        disableSleepDuringDischarge: Bool,
        sailingEnabled: Bool,
        sailingResumeLevel: Int?
    ) async {
        logger.debug("Update status")
        // Ahead of every guard below. The arm is what the removal rules are measured
        // against, and a pass that returns early — no mode yet, no licence, charging not
        // managed — must not be the one that loses it.
        let overrideArm = noteTempOverrideArm(userTempChargingMode, batteryLevel: powerState.batteryLevel)
        let appChargingMode = await appChargingState.currentAppChargingMode()
        var currentMode = appChargingMode.mode
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
        // configured limit only when there's no manual temp override (which still wins). Its
        // resume level replaces the main screen's sailing settings on the same terms.
        let automationTarget = await appChargingState.currentAutomationTarget()
        let effectiveChargeLimit = automationTarget?.limit ?? chargeLimit

        guard currentMode != .initial else {
            logger.debug("We don't have a mode yet")
            await analytics.addBreadcrumb(category: .chargingManager, message: "App mode is still set to initial")
            await fetchAndUpdateAppChargingState()
            return
        }

        switch licenseStatus.chargeManagement {
        case .manage:
            break
        case .waitForLicence:
            // Not read from the keychain yet, which at launch can outlast the first passes.
            // Handing back here released BatFi's limit for the moment the read took, and on
            // macOS 27 below 80% applying it again then waited up to 45 s for powerd — on the
            // first plug-in after a boot, the icon with it. Nothing is applied or released;
            // the licence arriving re-drives the state. The connection still goes out, the
            // same way it does ahead of the apply below, so the icon follows a plug-in now.
            logger.notice("License not read yet; waiting for it before managing charging")
            if let connection = ChargerConnection.connectionToPublishAheadOfMode(
                published: await appChargingState.currentAppChargingMode(),
                resolved: chargerConnected
            ) {
                await appChargingState.setChargerConnectedAheadOfMode(connection)
            }
            return
        case .handBack:
            logger.notice("License not activated")
            forgetSailingPhase(because: "charging is handed back to macOS")
            await disengage(chargerConnected: chargerConnected)
            return
        }

        // The override the limit and the band are worked out from. Under `.firmwareRange` an
        // override the band cannot hold — "Run on Battery"'s 0% — is left out of both, so the
        // band stays armed as it would be without it and nothing is written when the discharge
        // starts or ends; the discharge is BatFi's own and the mode decision below reads it
        // from the real override (`FirmwareRangeDischarge`). Every other backend gets the
        // override itself. The backend is only asked with an override in force.
        let overrideForLimit = userTempChargingMode == nil
            ? nil
            : FirmwareRangeDischarge.overrideForLimit(userTempChargingMode, backend: await chargeBackend())
        noteOverrideLeftOutOfFirmwareBand(overrideForLimit == userTempChargingMode ? nil : userTempChargingMode)

        // Advanced once per pass, before anything reads it: the delay-sleep rule below and the
        // mode decision further down. Not while charging is not managed, which hands charging
        // back below and leaves the phase meaning nothing.
        var sailing: (levels: SailingLevels?, phase: SailingPhase?, firmwareBandResumeLevel: Int?, startedAfresh: Bool)
        if manageCharging {
            sailing = await advanceSailing(
                powerState: powerState,
                chargerConnected: chargerConnected,
                userTempChargingMode: userTempChargingMode,
                overrideForLevels: overrideForLimit,
                targetLimit: overrideForLimit?.limit
                    ?? ChargeToFullHold.requestedLimit(holding: holdingFullChargeUntilUnplugged, otherwise: effectiveChargeLimit),
                chargeLimit: chargeLimit,
                sailingEnabled: sailingEnabled,
                sailingResumeLevel: sailingResumeLevel,
                automationTarget: automationTarget
            )
        } else {
            forgetSailingPhase(because: "charge management is off")
            sailing = (nil, nil, nil, false)
        }

        // The resolved value, not the raw one: releasing the prevent-automatic-sleep
        // assertion mid-discharge lets the Mac auto-sleep with force discharge latched in
        // the SMC.
        //
        // Not engaged where BatFi cannot pause charging: there the firmware or macOS holds
        // the limit while the Mac sleeps, and the battery can sit just below it for hours,
        // which kept the Mac from ever auto-sleeping on AC. An unknown backend keeps the
        // assertion, the same fail-open rule `backendCanPauseChargingOnDemand` follows —
        // `DelayAutomaticSleep` holds the rule and its tests. The backend is only asked
        // for when the setting is on, so a pass with it off never makes the XPC call.
        let delaySleepBackend = preventAutomaticSleep ? await chargeBackend() : nil
        await setUpDelaySleep(
            DelayAutomaticSleep.shouldPreventAutomaticSleep(
                enabled: preventAutomaticSleep,
                batteryLevel: powerState.batteryLevel,
                limit: userTempChargingMode?.limit ?? effectiveChargeLimit,
                chargerConnected: chargerConnected,
                backend: delaySleepBackend,
                sailingIsHolding: sailing.phase == .holding
            )
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
        // which beats the user's configured one — with a charge-to-full hold slotted in
        // between the two, above automation exactly as the override it came from was. The
        // hold *is* this substitution: with 100 requested, the no-override branch below
        // inhibits at 100% and charges at 99% on its own, `systemChargeAboveLimit`'s
        // `level > limitInForce` guard stays false, and nothing discharges a battery the
        // user asked to have filled.
        //
        // A hot-battery hold goes on top of all of them, on `.systemChargeLimit` only: there
        // the cutout *is* this substitution (`HotBatteryHold`), and it beats the override
        // and the charge-to-full hold exactly as the inhibit beats them on the backends that
        // have one. It takes the lower of the two values, so a discharge — or the user
        // lowering the slider — still goes ahead.
        let limitWithoutHotBatteryHold = overrideForLimit?.limit
            ?? ChargeToFullHold.requestedLimit(holding: holdingFullChargeUntilUnplugged, otherwise: effectiveChargeLimit)
        await updateHotBatteryHold(
            isEnabled: turnOffChargingWithHotBattery,
            temperature: powerState.batteryTemperature,
            chargerConnected: chargerConnected,
            batteryLevel: powerState.batteryLevel
        )
        let hotBatteryHoldIsActive = hotBatteryHoldLimit != nil
        // Sailing's hold where macOS enforces the limit is the value kept in force, beneath the
        // hot battery's, which beats it as it beats everything else (`SailingLimitHold`); a hold
        // takes a lower hot value over, so the hot hold's release writes nothing. The backend
        // is only asked with a phase, so with sailing off this asks nothing.
        let sailingBackend = sailing.phase != nil ? await chargeBackend() : nil
        let sailingKeptLimit = sailingLimitHold.requestedLimit(
            phase: sailing.phase,
            backend: sailingBackend,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitRaiseWindow.lastAppliedLimit,
            otherwise: limitWithoutHotBatteryHold,
            floor: applyFloor,
            hotBatteryHoldLimit: hotBatteryHoldLimit
        )
        // Where the firmware holds a band, a sailing hold that began below the limit is the band
        // with its upper bound at the battery (`FirmwareSailingHold`): that stops charging, a
        // charge in progress included, and the lower bound at the resume level keeps it stopped
        // until the battery is below it. Nil at the limit and in every other case, where the
        // pass requests what it would without it. A phase only exists here where the helper
        // takes the two-value call (`advanceSailing`).
        let firmwareSailingBand = firmwareSailingHold.heldBand(
            phase: sailing.phase,
            backend: sailingBackend,
            startedAfresh: sailing.startedAfresh,
            batteryLevel: powerState.batteryLevel,
            levels: sailing.firmwareBandResumeLevel != nil ? sailing.levels : nil
        )
        noteFirmwareSailingBandChange(
            firmwareSailingBand,
            batteryLevel: powerState.batteryLevel,
            levels: sailing.levels
        )
        let requestedLimit = HotBatteryHold.requestedLimit(
            frozenAt: hotBatteryHoldLimit,
            otherwise: firmwareSailingBand?.limit ?? sailingKeptLimit
        )
        // What a pause armed now would be judged against, for the menu: it offers Inhibit
        // Charging and Pause Discharging only where they would hold (`ManualInhibit.holds`).
        // Ahead of the apply, which can wait 45 s on powerd, so an older pass suspended in it
        // never publishes over a newer one; and from the request, not the applied value, which
        // lags it by as long.
        await appChargingState.setPauseContext(await pauseHoldContext(overrideInForce: userTempChargingMode))
        // A manual inhibit on `.systemChargeLimit` is already in `requestedLimit` — it is the
        // override — so there is nothing to substitute. What it shares with the hot hold is
        // everything downstream: the limit in force is BatFi's own short-lived value, frozen
        // at the battery's level, not the user's. The backend is only asked for when an
        // inhibit is armed; it is cached after the first answer anyway.
        let manualInhibitIsHeld = await updateManualInhibitHold(
            userTempChargingMode: userTempChargingMode,
            batteryLevel: powerState.batteryLevel
        )
        // Published once per pass, after every event that could have moved the flag above
        // (a new override arm, an unplug) and before the mode decision reads it, so the
        // label and the limit in force always describe the same pass. Not while a hot battery
        // is held: the limit in force is then the frozen one, and "Holding 100% until
        // unplugged" would describe a request that is waiting for the battery to cool. The
        // flag itself is kept, so the hold resumes when the hot one ends.
        await appChargingState.setHoldingFullChargeUntilUnplugged(
            holdingFullChargeUntilUnplugged && !hotBatteryHoldIsActive
        )
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
        //
        // The connection goes out first, though. The apply can be slow — on macOS 27 with a
        // sub-80% limit the helper waits up to 45 s for powerd to adopt it, and powerd's policy
        // list is empty on battery, so the first pass after every plug-in pays that in full —
        // and every applier below publishes the connection only once it has run. The icon sat
        // on the old connection for the whole wait. Published as *ahead of its mode*, because
        // the mode is still the one from before the change: the banner waits for the applier,
        // which publishes the connection again beside the mode it derived and clears the mark.
        // Read afresh rather than from the top of the pass: there have been awaits since, and
        // another pass may already have published this connection with its mode.
        if let connection = ChargerConnection.connectionToPublishAheadOfMode(
            published: await appChargingState.currentAppChargingMode(),
            resolved: chargerConnected
        ) {
            await appChargingState.setChargerConnectedAheadOfMode(connection)
        }
        // A raise over a battery below it is shown as charging before the apply, which on
        // macOS 27 can wait up to 45 s for powerd, and a lowering under it as held: every
        // change the user asks for is shown at once. See `ChargingAheadOfApply`.
        if await publishModeAheadOfApply(
            powerState: powerState,
            chargerConnected: chargerConnected,
            requestedLimit: requestedLimit,
            overrideOfThisPass: userTempChargingMode,
            sailingResumeLevel: sailing.phase == .holding ? sailing.levels?.resumeLevel : nil
        ) {
            // What the hardware was just told, so the mode decision does not send it again.
            currentMode = await appChargingState.currentAppChargingMode().mode
        }
        // The band's resume level goes with the limit only where it was worked out for this
        // very limit; any other request is applied alone, as it is with sailing off.
        // A held band goes out with its own lower bound.
        let requestedBandResumeLevel: Int?
        if let firmwareSailingBand, firmwareSailingBand.limit == requestedLimit {
            requestedBandResumeLevel = firmwareSailingBand.resumeLevel
        } else {
            requestedBandResumeLevel = sailing.levels?.limit == requestedLimit ? sailing.firmwareBandResumeLevel : nil
        }
        let appliedLimit = await applyChargeLimit(requestedLimit, resumeLevel: requestedBandResumeLevel)
        let effectiveLimitInForce = appliedLimit ?? requestedLimit
        // A held band the client sent as the one-value call — the helper refused it — is not in
        // force: the firmware got a narrow band under the held value instead. BatFi stops holding
        // the band itself, and from the next pass the firmware decides, as before.
        if appliedLimit != nil, let firmwareSailingBand, firmwareSailingBand.limit == requestedLimit {
            let wentOut = firmwareBandHandover.bandResumeLevel(
                limit: firmwareSailingBand.limit,
                requestedResumeLevel: firmwareSailingBand.resumeLevel
            ) != nil
            firmwareSailingHold.recordApply(of: firmwareSailingBand, wentOutAsRange: wentOut)
            if !wentOut {
                logger.notice("Sailing: the helper did not take the held band \(firmwareSailingBand.resumeLevel, privacy: .public)-\(firmwareSailingBand.limit, privacy: .public)%; leaving the hold to the firmware")
                sailingTracker.forget()
            }
        }
        // A sailing hold the apply put above the battery cannot stand: macOS charges up to the
        // raised value. That is the first sub-80 request of a process on a Mac that refuses
        // one, before its floor was learned. The owner's fallback for those Macs: charge to the
        // limit and sail from there — this pass too, so the label never says "on hold" over a
        // battery taking charge. Not under a hot battery's hold, which is what is in force.
        //
        // The apply can wait 45 s on powerd, and a pass that ran meanwhile — an unplug — may
        // have forgotten the phase or moved it on: the tracker and the kept value are then
        // that pass's, and this one leaves them alone.
        if sailing.phase == .holding, sailingTracker.phase == .holding, !hotBatteryHoldIsActive, sailingLimitHold.heldLimit != nil,
           SailingLimitHold.applyRaisedItAboveTheBattery(
               requested: requestedLimit,
               applied: appliedLimit,
               batteryLevel: powerState.batteryLevel
           ) {
            logger.notice("Sailing: macOS applied \(effectiveLimitInForce, privacy: .public)% for a \(requestedLimit, privacy: .public)% hold with the battery at \(powerState.batteryLevel, privacy: .public)%; charging to the limit first")
            sailingTracker.chargeToLimitFirst()
            sailingLimitHold = SailingLimitHold()
            sailing.phase = .charging
        }
        // A sailing hold that keeps a value other than the person's limit is BatFi's own
        // short-lived value, like a hot battery's or a manual pause's: the drift warning, the
        // top-up and drain labels and the nudge treat it as one. A hold at the person's own
        // limit is not, so macOS's top-up there is told as it is with sailing off.
        let systemSailingFreezeIsInForce = sailingLimitHold.keepsAValueOtherThan(limitWithoutHotBatteryHold)
        noteSailingFreezeChange(isInForce: systemSailingFreezeIsInForce, limit: sailingLimitHold.heldLimit)
        // The firmware's held band is the same kind of value: BatFi's own, under the person's
        // limit, for the length of the hold.
        let firmwareSailingHoldIsInForce = firmwareSailingHold.keepsAValueOtherThan(limitWithoutHotBatteryHold)
        let sailingFreezeIsInForce = systemSailingFreezeIsInForce || firmwareSailingHoldIsInForce
        let frozenLimitIsInForce = hotBatteryHoldIsActive || manualInhibitIsHeld || sailingFreezeIsInForce
        // What the mode decision judges the battery against. Under a sailing freeze that is the
        // limit the person has — where macOS will enforce it — not the frozen value, so the
        // phase and the rule agree on what "the limit" is. A hot battery's hold outranks it and
        // is judged as it always was.
        // Under the firmware's held band it is the person's limit itself, so the battery under it
        // reads as sailing's hold, never as at the limit.
        let decisionLimit: Int
        if firmwareSailingHoldIsInForce {
            decisionLimit = limitWithoutHotBatteryHold
        } else if systemSailingFreezeIsInForce, !hotBatteryHoldIsActive {
            decisionLimit = SailingLimitHold.limitMacOSEnforces(requested: limitWithoutHotBatteryHold, floor: applyFloor)
        } else {
            decisionLimit = effectiveLimitInForce
        }
        // The band the pass measures and names: the asked-for one only where the helper was
        // actually handed it. The client sends the one-value call in its place to a helper too
        // old for the range, one whose version it cannot read, or one that refused this range,
        // and the firmware then keeps today's band — `FirmwareBandHandover`.
        let bandResumeLevel = firmwareBandHandover.bandResumeLevel(
            limit: requestedLimit,
            requestedResumeLevel: requestedBandResumeLevel
        )
        noteFirmwareBandChange(resumeLevel: bandResumeLevel, limit: requestedLimit)
        // The resume level the pass names when it holds for sailing — at the limit as well as
        // inside the range, so the label does not change as the battery leaves the limit.
        // Always the person's resume level, never a held band's lower bound, which can sit a
        // point under it. Where the firmware decides (no two-value call) there is no phase:
        // the level is the one the band was handed with, named whenever the firmware is seen
        // holding (at the limit, or measured inside the band by `FirmwareRangeHold`) and
        // never otherwise.
        let sailingHoldLevel = sailing.phase == .holding ? sailing.levels?.resumeLevel : bandResumeLevel

        // Asked again, because the apply can wait up to 45 s and the licence guard above was
        // answered before it. A licence revoked in that time drives a pass of its own, which
        // hands charging back while this one is suspended; carrying on would run an applier
        // after it and enforce again with no licence. The handing back is that pass's job —
        // it has done it or is about to — so this one only stops.
        guard licenseStatus.chargeManagement == .manage else {
            logger.notice("License changed while the charge limit was applied; not managing charging")
            return
        }

        // powerd's enforced limit, read once per pass (one small file read, only on a
        // mechanism that owns the charging decision), and what it says about a change. The
        // limit applied above is what BatFi asked for; powerd takes up to 45 s to adopt it,
        // and current and IOKit lag up to ~45 s behind that. In all of it a battery about to
        // charge reads as held below a raised limit, and one still charging reads as charging
        // past a lowered one — see `ChargeLimitRaiseWindow`. The state the user asked for is
        // what the menu shows, and is held through it.
        //
        // Ahead of the drift check, because both read the firmware's hold attribution, which
        // is cached for five minutes: one read before a limit changed is about the old limit,
        // and is dropped here so the next ask is fresh.
        let enforcedLimit = await systemDischargesToLimitItself() ? PowerdChargePolicy.enforcedLimit() : nil
        // A failed apply is not recorded as applying the request it fell back to: a request
        // the mechanism cannot express would make the next success read as a raise.
        let limitRaise = limitRaiseWindow.record(
            enforced: enforcedLimit,
            applied: effectiveLimitInForce,
            appliedWasConfirmed: appliedLimit != nil,
            changesAwaitPowerd: HotBatteryHold.applies(to: await chargeBackend()),
            now: date.now
        )
        if limitRaise.enforcedLimitChanged || limitRaise.appliedLimitChanged {
            lastHoldAttributionAt = nil
            lastHoldAttribution = nil
        }
        // "Resume Discharging" under Apple's charge limit was shown as macOS draining at the
        // click; through the lowering's window, which holds the drain back with the other
        // above-limit states, it stays shown. See `DischargeResumeHold`.
        dischargeResumeHold.record(
            suppressesAboveLimitStates: limitRaise.suppressesAboveLimitStates,
            overrideInForce: userTempChargingMode,
            passIsStale: userTempChargingMode != (await appChargingState.currentUserTempOverrideMode())
        )
        let drainIsHeld = dischargeResumeHold.holdsDrain(
            batteryLevel: powerState.batteryLevel,
            limitInForce: effectiveLimitInForce,
            overrideInForce: userTempChargingMode
        )

        // What macOS is doing to a battery above the limit, worked out once and read twice —
        // by the drift check immediately below and by the mode decision further down. Both
        // have to see the same answer: the drift check's whole job is deciding whether this
        // reading is a fault, and the label's is saying what it is, and those two disagreeing
        // is how a user came to be shown "Discharging to the limit" and warned that the limit
        // was not holding, about one battery, at the same moment.
        //
        // **Both flags go to the drift check, not just the top-up.** They exclude the two
        // states that wear the fault's shape without being one, and the drain needs saying out
        // loud: while the top-up flag was wrongly set during a drain it was suppressing the
        // drift arm by accident, and correcting the direction took that accident away.
        //
        // The label gets the latched answer and the drift check the reading's own, so the
        // latch changes what the menu says and not when a limit is re-applied. The latched
        // top-up still keeps the drift *warning* back, as the top-up always has.
        //
        // Not while a lowering is still being adopted: the battery charging on under powerd's
        // old limit is not macOS charging past the new one, and the labels are held back the
        // way a frozen limit holds them (`ChargeLimitRaiseWindow.suppressesAboveLimitStates`).
        let aboveLimit = await systemChargeAboveLimit(
            powerState: powerState,
            chargerConnected: chargerConnected,
            limitInForce: effectiveLimitInForce,
            frozenLimitIsInForce: frozenLimitIsInForce || limitRaise.suppressesAboveLimitStates
        )

        // Asked of the battery rather than of the mechanism, and asked after the limit has
        // been put in force so that both are read on the same pass. Nor during a lowering's
        // window: the run is reset, so a fault after it has to last its full minute.
        if limitRaise.suppressesAboveLimitStates {
            driftMonitor = ChargeHoldDriftMonitor()
        } else {
            await checkForChargeHoldDrift(
                powerState: powerState,
                chargerConnected: chargerConnected,
                requestedLimit: requestedLimit,
                bandResumeLevel: bandResumeLevel,
                limitInForce: effectiveLimitInForce,
                currentMode: currentMode,
                systemIsChargingPastLimit: aboveLimit.snapshotIsToppingUp,
                systemIsDrainingToLimit: aboveLimit.snapshotIsDraining,
                systemTopUpIsLatched: aboveLimit.isToppingUp,
                frozenLimitIsInForce: frozenLimitIsInForce
            )
        }

        // Answered once per pass, here rather than inside the mode decision, and answered on
        // **every** pass rather than only on the branch that consumes it. The monitor below
        // needs the clean readings as much as the held ones: its clock is reset by them, and a
        // clock left half-elapsed by a pass that never asked would fire a write within seconds
        // of the next dip instead of after a minute of it.
        let systemIsHoldingBelowLimit = await systemIsHoldingChargeBelowLimit(
            powerState: powerState,
            chargerConnected: chargerConnected,
            limitInForce: effectiveLimitInForce,
            enforcedLimit: enforcedLimit,
            holdVerdictIsHeldBack: limitRaise.suppressesHold,
            currentMode: currentMode
        )
        // Never while a frozen limit is in force — a hot battery's, or a manual inhibit's. The
        // nudge exists to get charging going again, and it does it by raising the limit three
        // points above the one in force — here the frozen one — which would resume charging
        // the battery the hold is there to stop. Reported as not holding rather than skipped,
        // so the monitor's clock is reset and a stall after the hold ends has to last its full
        // minute before anything is written.
        //
        // Nor while powerd is still adopting a raised limit, or charge has not had time to
        // start after it did, which needs no term of its own: the hold gives no verdict then
        // (`ChargeLimitRaiseWindow`).
        //
        // Nor while sailing holds: the stall is the hold. Once the phase turns to charging the
        // nudge is what resumes the charge macOS will not resume by itself.
        await checkForChargeResumeStall(
            isHolding: systemIsHoldingBelowLimit && !frozenLimitIsInForce && sailing.phase != .holding,
            target: requestedLimit,
            now: date.now
        )

        // A pass that worked its limit out under an override the user has since ended or
        // replaced — suspended in an apply that waits on powerd — publishes no mode: it would
        // be the old override's, put back over what the pass after the click has shown. That
        // pass, or the next, decides with the override in force.
        if userTempChargingMode != (await appChargingState.currentUserTempOverrideMode()) {
            logger.notice("The override changed while this pass applied its limit; leaving the mode to the next pass")
            return
        }

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
            // protection, which under `.firmwareRange` cannot be fixed and is disclosed instead.
            //
            // `.systemChargeLimit` is the exception that no longer needs the inhibit: the hot
            // hold has already been substituted into the limit applied above, so macOS is
            // holding charge at the frozen value and the mode decision below — keyed on the
            // limit in force — labels it like any other limit. Calling the inhibit here would
            // be the no-op that claimed `.inhibit` on its own, the bug above.
            if await backendCanPauseChargingOnDemand() {
                await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
                return
            }
            if HotBatteryHold.applies(to: await chargeBackend()) {
                logger.debug("Battery is hot; held by the frozen charge limit, \(self.hotBatteryHoldLimit.map(String.init) ?? "none (charger not connected)", privacy: .public)")
                break
            }
            logger.notice("Battery is hot but this Mac's charge mechanism cannot pause charging on demand; not claiming a pause")
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
            // Never a pause: "Pause Discharging" at a full battery is an override at 100 too,
            // and one that dipped a point before its arm was noted would otherwise "complete".
            if userTempChargingMode?.isInhibit != true, ChargeToFullCompletion.isReached(
                overrideLimit: tempLimit,
                batteryLevel: currentBatteryLevel,
                batteryLevelWhenArmed: overrideArm?.batteryLevel ?? currentBatteryLevel
            ) {
                logger.notice("Battery reached 100%, removing charge-to-full override")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Battery reached 100%, removing charge-to-full override")
                removeTempOverride()
                // The override is retired, but the request it expressed is not finished: the
                // user asked for a full battery and handing the limit straight back would take
                // it away again within seconds — by draining it, where discharging is allowed.
                // BatFi goes on requesting 100 instead, until the charger comes out. See
                // `ChargeToFullHold`.
                holdingFullChargeUntilUnplugged = ChargeToFullHold.next(
                    holding: holdingFullChargeUntilUnplugged,
                    event: .chargeToFullCompleted
                )
                await appChargingState.setHoldingFullChargeUntilUnplugged(holdingFullChargeUntilUnplugged)
                logger.notice("Charged to 100% as asked; holding it until the charger is unplugged")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Charged to 100% as asked; holding it until the charger is unplugged")
                await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
                return
            }
            // Symmetric to the charge-to-full removal above: an override the battery has
            // reached, on a backend that cannot hold it, is retired rather than left cycling
            // the battery — except a manual inhibit held by freezing Apple's limit, which is
            // armed at the level it holds. See `TempOverrideTargetReached`.
            if let userTempChargingMode,
               TempOverrideTargetReached.retires(
                   userTempChargingMode,
                   batteryLevel: currentBatteryLevel,
                   backend: await chargeBackend()
               ) {
                logger.notice("Discharge target reached and this Mac's charge mechanism cannot hold it; removing the override")
                await analytics.addBreadcrumb(category: .chargingManager, message: "Discharge target reached on a backend that cannot hold it; removing override")
                removeTempOverride()
                return await turnOnCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            }
            handleRemovingTempOverrideOnDisconnect(
                chargerConnected: chargerConnected,
                batteryLevel: currentBatteryLevel,
                overrideLimit: tempLimit,
                armedAt: overrideArm?.armedAt,
                overrideIsFrozenInhibit: manualInhibitIsHeld
            )
            // A manual inhibit under Apple's charge limit is shown as the pause from the click
            // and goes straight to the inhibit arm below, even while powerd is still adopting
            // the frozen limit and the battery charges on under the old one: every change the
            // user asks for is shown at once, and held through powerd's window
            // (`ChargeLimitRaiseWindow`). It used to report `.charging` until powerd enforced
            // the frozen value.
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
            //
            // Never for a manual inhibit held by the frozen limit. A battery above it is one
            // that crept up a point while powerd adopted the new limit, or one rounded down
            // from an off-step level from 80 up — and macOS drains to the limit in force by
            // itself there. Running `CHIE` on top would turn "stop charging" into BatFi's own
            // discharge, with sleep disabled for it. It falls through to the inhibit below.
            if currentBatteryLevel > tempLimit, isLidOpenedOrSleepDisabled, !manualInhibitIsHeld {
                return await turnOnDischarging(
                    chargerConnected: chargerConnected,
                    disableSleep: sleepIsDisabledForDischarge,
                    currentMode: currentMode
                )
            } else if ChargeDecisionRule.chargeOrHold(
                batteryLevel: currentBatteryLevel,
                limitInForce: decisionLimit,
                sailingPhase: sailing.phase
            ) == .charge, await !firmwareSailingBandIsHolding(
                bandResumeLevel: bandResumeLevel,
                powerState: powerState,
                chargerConnected: chargerConnected,
                limitInForce: effectiveLimitInForce,
                currentMode: currentMode
            ) {
                return await turnOnCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            } else {
                // A temporary limit sails at the main screen's distance below it; a pause never does, so the bookkeeping
                // below never meets a sailing hold.
                let inhibited = await inhibitCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode,
                    sailingResumeLevel: sailingHoldLevel
                )
                // On the backends that pause on demand the SMC inhibit is the pause, shown from
                // the click. A failed write is retried by the next pass; one that keeps failing
                // leaves the battery charging under "Charging paused", so the pause is ended
                // rather than kept claiming, and the real state shows. Judged on this write's
                // own result, not on the published mode read back after it.
                if let userTempChargingMode, userTempChargingMode.isInhibit, !manualInhibitIsHeld,
                   inhibitWriteFailures.record(succeeded: inhibited, for: userTempChargingMode) {
                    logger.error("Inhibit charging: the SMC inhibit failed \(InhibitWriteFailures.threshold, privacy: .public) passes in a row; ending the pause at \(userTempChargingMode.limit, privacy: .public)% rather than claiming it while the battery charges")
                    await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging write kept failing; pause ended")
                    // A discharge pause puts back the discharge it replaced, as Resume would.
                    await appChargingState.endOverride(
                        userTempChargingMode,
                        .afterFailedInhibitWrites(ending: userTempChargingMode)
                    )
                }
                return
            }
        } else {
            // The decision itself is `ChargeDecisionRule`; this arm only answers its questions
            // and carries the answer out. Three of those questions reach the backend or the
            // helper — a diagnostics call the first time the backend is asked for, and an SMC
            // power read with a transition log behind `firmwareRangeIsHoldingCharge` — so each
            // is asked only on the passes the rule would read it, exactly where the inline
            // chain used to ask it, and is `false` everywhere else. On those passes the rule's
            // outcome does not depend on it.
            //
            // `computerIsAsleep` is read once, before any of them, as the inline chain read it
            // ahead of its first `await` on every path.
            let isAsleep = computerIsAsleep
            let isAboveLimit = currentBatteryLevel > decisionLimit
            let isBelowLimit = currentBatteryLevel < decisionLimit

            // Under Apple's charge limit macOS performs the above-limit discharge itself; only
            // asked once every other condition for BatFi's own discharge holds.
            let systemDrainsToLimit: Bool
            if isAboveLimit, allowDischarging, isLidOpenedOrSleepDisabled, !isAsleep {
                systemDrainsToLimit = await systemDischargesToLimitItself()
            } else {
                systemDrainsToLimit = false
            }

            // Same gate as the `willSleep` hook, and it has to be here too: a poll can land
            // while the Mac is asleep, and this is what would pin the app to `.inhibit` for the
            // rest of the sleep on a mechanism that never paused anything.
            let pausesForSleep: Bool
            if isBelowLimit, inhibitChargingOnSleep, isAsleep {
                pausesForSleep = await backendCanPauseChargingOnDemand()
            } else {
                pausesForSleep = false
            }

            // Only below the limit, and only once none of the sleep pause, sailing's hold and
            // macOS's own hold has already settled the pass.
            let firmwareRangeIsHolding: Bool
            if isBelowLimit, !pausesForSleep, sailing.phase != .holding, !systemIsHoldingBelowLimit {
                firmwareRangeIsHolding = await firmwareRangeIsHoldingCharge(
                    powerState: powerState,
                    chargerConnected: chargerConnected,
                    limitInForce: effectiveLimitInForce,
                    resumeLevel: bandResumeLevel,
                    currentMode: currentMode
                )
            } else {
                firmwareRangeIsHolding = false
            }

            let decision = ChargeDecisionRule.decide(ChargeDecisionInputs(
                batteryLevel: currentBatteryLevel,
                limitInForce: decisionLimit,
                allowDischarging: allowDischarging,
                lidOpenOrSleepDisabled: isLidOpenedOrSleepDisabled,
                computerIsAsleep: isAsleep,
                systemDischargesToLimitItself: systemDrainsToLimit,
                pausesChargingForSleep: pausesForSleep,
                systemIsHoldingBelowLimit: systemIsHoldingBelowLimit,
                firmwareRangeIsHolding: firmwareRangeIsHolding,
                sailingPhase: sailing.phase
            ))
            await perform(
                decision,
                chargerConnected: chargerConnected,
                currentMode: currentMode,
                sleepIsDisabledForDischarge: sleepIsDisabledForDischarge,
                systemIsDischargingToLimit: aboveLimit.isDraining || drainIsHeld,
                systemIsChargingPastLimit: aboveLimit.isToppingUp && !drainIsHeld,
                sailingHoldLevel: sailingHoldLevel
            )
        }
    }

    /// Carries out what `ChargeDecisionRule` decided for a pass with no override in force,
    /// with the arguments each mode has always been entered with.
    ///
    /// - Parameters:
    ///   - systemIsDischargingToLimit: macOS draining to the limit in force, or the drain held
    ///     back by `DischargeResumeHold`. Read only at the limit.
    ///   - systemIsChargingPastLimit: macOS topping up past the limit, with no drain held.
    ///     Read only at the limit.
    ///   - sailingHoldLevel: the resume level while sailing holds, or nil. Read at the limit
    ///     and by the sailing hold.
    private func perform(
        _ decision: ChargeDecision,
        chargerConnected: Bool,
        currentMode: ChargingMode,
        sleepIsDisabledForDischarge: Bool,
        systemIsDischargingToLimit: Bool,
        systemIsChargingPastLimit: Bool,
        sailingHoldLevel: Int?
    ) async {
        switch decision {
        case .discharge:
            await turnOnDischarging(
                chargerConnected: chargerConnected,
                disableSleep: sleepIsDisabledForDischarge,
                currentMode: currentMode
            )
        case .inhibitAtLimit:
            // `.inhibit` is the honest mode here — charge is being held — but on a mechanism
            // that drains to the limit itself it is being held by macOS, which is also actively
            // running the battery *down* to get there. Keyed on the limit **in force** rather
            // than the one requested because that is the value the system drains to.
            // While sailing it is also the top of the hold, named as one so the label does not
            // change as the battery leaves the limit.
            await inhibitCharging(
                chargerConnected: chargerConnected,
                currentMode: currentMode,
                systemIsDischargingToLimit: systemIsDischargingToLimit,
                systemIsChargingPastLimit: systemIsChargingPastLimit,
                sailingResumeLevel: sailingHoldLevel
            )
        case .inhibitForSleep:
            await inhibitCharging(
                chargerConnected: chargerConnected,
                currentMode: currentMode
            )
        case .inhibitForSailing:
            // Reached where sailing keeps a phase (`advanceSailing`): on a backend that pauses on
            // demand, where the SMC inhibit is the hold, and under `.systemChargeLimit`, where
            // the hold is the limit kept in force (`SailingLimitHold`) and the inhibit names it.
            // Published with the level charging resumes below.
            await inhibitCharging(
                chargerConnected: chargerConnected,
                currentMode: currentMode,
                sailingResumeLevel: sailingHoldLevel
            )
        case .inhibitBySystemHold:
            // Below the limit and *still* not charging, with the firmware naming Apple's own
            // limit as the reason. `turnOnCharging` would write nothing at all here and report
            // `.charging` for a battery at 0 mA: measured on 26A5416b at 56% against a 60%
            // limit, for two hours, while the menu read "Charging to the limit".
            await inhibitCharging(
                chargerConnected: chargerConnected,
                currentMode: currentMode,
                systemIsHoldingBelowLimit: true
            )
        case .inhibitByFirmwareRange:
            // Labelled as the plain inhibit, not the held-below-limit sub-state: that one names
            // macOS as the actor, and here the hold is BatFi's own limit, the same one the menu
            // shows at the limit. The step from the limit into the drift therefore changes
            // nothing on screen and posts no banner; the band's two real edges — charging
            // resumes at the lower bound, stops at the limit — each still do, once per cycle.
            // With sailing the band reaches down to the resume level, named here as it is at
            // the limit, so the step into the drift still changes nothing on screen.
            await inhibitCharging(
                chargerConnected: chargerConnected,
                currentMode: currentMode,
                sailingResumeLevel: sailingHoldLevel
            )
        case .charge:
            await turnOnCharging(
                chargerConnected: chargerConnected,
                currentMode: currentMode
            )
        }
    }

    /// Works out the levels sailing works against this pass and advances its phase, saying so
    /// when the phase changes.
    ///
    /// Sailing follows its phase on a backend BatFi pauses on demand (`.chte`,
    /// `.legacyCH0BC`), where the SMC inhibit is the hold, and under `.systemChargeLimit`, where
    /// the hold is the limit kept in force (`SailingLimitHold`) and the limit is judged where
    /// the apply will put it. Under `.firmwareRange` BatFi hands the firmware a band reaching
    /// down to the resume level (`firmwareBandResumeLevel`) and, where the helper takes the
    /// two-value call, follows the phase too: a hold below the limit is the band's upper bound
    /// at the battery (`FirmwareSailingHold`). Where it takes only the one-value call — an older
    /// helper, or this band refused — the firmware decides when to charge and BatFi labels what
    /// it measures, so no phase is kept and the rule is fed none. Elsewhere, and while the
    /// backend is not known, nothing is in play and
    /// the pass behaves as it does without sailing. The backend is asked only where the settings
    /// that count this pass have sailing on (`SailingRange.switchIsOn`: an active rule's own,
    /// else the main screen's), so a pass with it off makes no helper call.
    ///
    /// The levels and the override go to the tracker from this same pass, so a temporary limit
    /// is judged against the levels it set, and a rule taking over or edited during a hold is a
    /// level change the tracker keeps the phase through unless the new levels contradict it.
    ///
    /// `overrideForLevels` is the override the levels are worked out from — the real one,
    /// except under `.firmwareRange` for one the band cannot hold (`FirmwareRangeDischarge`),
    /// where the band keeps the levels it has without the override. The tracker always gets
    /// the real one.
    private func advanceSailing(
        powerState: PowerState,
        chargerConnected: Bool,
        userTempChargingMode: UserTempChargingMode?,
        overrideForLevels: UserTempChargingMode?,
        targetLimit: Int,
        chargeLimit: Int,
        sailingEnabled: Bool,
        sailingResumeLevel: Int?,
        automationTarget: AutomationTarget?
    ) async -> (levels: SailingLevels?, phase: SailingPhase?, firmwareBandResumeLevel: Int?, startedAfresh: Bool) {
        let switchIsOn = SailingRange.switchIsOn(
            mainSwitch: sailingEnabled,
            automation: automationTarget,
            overrideInForce: overrideForLevels
        )
        let backend = switchIsOn ? await chargeBackend() : nil
        let firmwareHoldsTheBand = backend == .firmwareRange
        let macOSEnforcesTheLimit = backend == .systemChargeLimit
        let levels = SailingRange.levelsInPlay(
            enabled: sailingEnabled,
            backendCanSail: backend?.canPauseChargingOnDemand == true || firmwareHoldsTheBand || macOSEnforcesTheLimit,
            targetLimit: macOSEnforcesTheLimit
                ? SailingLimitHold.limitMacOSEnforces(requested: targetLimit, floor: applyFloor)
                : targetLimit,
            configuredLimit: ChargeLimitRange.displayedLimit(configured: chargeLimit, for: backend),
            configuredResume: sailingResumeLevel,
            automation: automationTarget,
            overrideInForce: overrideForLevels,
            holdingFullChargeUntilUnplugged: holdingFullChargeUntilUnplugged
        )
        // Under `.firmwareRange` BatFi enforces the phase only where the band's lower bound
        // reaches the firmware: the two-value call for the real band, asked ahead. Otherwise
        // the firmware decides, as it did before BatFi held the band itself.
        var firmwareDecides = firmwareHoldsTheBand
        if firmwareHoldsTheBand, let levels, firmwareSailingHold.canHoldByBand {
            firmwareDecides = await !chargingClient.chargeRangeCallIsAvailable(levels.limit, levels.resumeLevel)
        }
        if firmwareDecides != firmwareSailingIsLeftToTheFirmware, levels != nil {
            firmwareSailingIsLeftToTheFirmware = firmwareDecides
            if firmwareHoldsTheBand {
                logger.notice("Sailing: \(firmwareDecides ? "the firmware decides when to charge (no two-value call)" : "BatFi holds the firmware band itself", privacy: .public)")
            }
        }
        let previous = sailingTracker.phase
        // No levels for the tracker where the firmware decides, which leaves it without a phase.
        var phase = sailingTracker.advance(
            chargerConnected: chargerConnected,
            levels: firmwareDecides ? nil : levels,
            overrideInForce: userTempChargingMode,
            batteryLevel: powerState.batteryLevel
        )
        // A hold that would begin by freezing the limit below 80 on a Mac that refuses one
        // cannot be expressed: there, and only there, charge to the limit and sail from there.
        // After `advance`, which would discard it on a fresh start.
        if sailingLimitHold.cannotHoldOnEntry(
            phase: phase,
            backend: backend,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitRaiseWindow.lastAppliedLimit,
            otherwise: targetLimit,
            floor: applyFloor
        ) {
            logger.notice("Sailing: this Mac cannot hold a limit below 80% at \(powerState.batteryLevel, privacy: .public)%; charging to the limit first")
            sailingTracker.chargeToLimitFirst()
            phase = sailingTracker.phase
        }
        // On the transition only, at notice: debug lines are absent from customer logs.
        if phase != previous {
            switch (phase, levels) {
            case (.holding?, let levels?):
                logger.notice("Sailing: holding charge at \(powerState.batteryLevel, privacy: .public)% until it is below \(levels.resumeLevel, privacy: .public)% (limit \(levels.limit, privacy: .public)%)")
            case (.charging?, let levels?):
                logger.notice("Sailing: charging from \(powerState.batteryLevel, privacy: .public)% to the \(levels.limit, privacy: .public)% limit (resumes below \(levels.resumeLevel, privacy: .public)%)")
            default:
                logger.notice("Sailing: phase forgotten (charger connected \(chargerConnected, privacy: .public), sailing in play \(levels != nil, privacy: .public))")
            }
        }
        let firmwareBandResumeLevel = firmwareHoldsTheBand ? levels?.resumeLevel : nil
        return (levels, phase, firmwareBandResumeLevel, sailingTracker.startedAfresh && phase != nil)
    }

    /// Says so when the band handed to the firmware changes. On a change only, at notice: the
    /// band is written once per change, and debug lines are absent from customer logs. With
    /// sailing off the level is always nil, as it starts, so this logs nothing.
    private func noteFirmwareBandChange(resumeLevel: Int?, limit: Int) {
        guard resumeLevel != lastFirmwareBandResumeLevel else { return }
        lastFirmwareBandResumeLevel = resumeLevel
        if let resumeLevel {
            logger.notice("Sailing: the firmware holds \(limit, privacy: .public)% and resumes below \(resumeLevel, privacy: .public)%")
        } else {
            logger.notice("Sailing: the firmware holds today's band")
        }
    }

    /// Says so each time the held sailing band changes — written, moved, or released — with what
    /// it was decided from, and resets the drift and nudge monitors on its start and end, as the
    /// kept limit's edges do. At notice: debug lines are absent from customer logs. With sailing
    /// off, or on any other backend, there is never a band, so this logs nothing.
    private func noteFirmwareSailingBandChange(
        _ band: FirmwareSailingHold.Band?,
        batteryLevel: Int,
        levels: SailingLevels?
    ) {
        guard band != lastFirmwareSailingBand else { return }
        let started = lastFirmwareSailingBand == nil
        lastFirmwareSailingBand = band
        let limit = levels.map { String($0.limit) } ?? "none"
        let resume = levels.map { String($0.resumeLevel) } ?? "none"
        if let band {
            if started {
                driftMonitor = ChargeHoldDriftMonitor()
                nudgeMonitor = ChargeResumeNudgeMonitor()
            }
            logger.notice("Sailing: holding with the firmware band \(band.resumeLevel, privacy: .public)-\(band.limit, privacy: .public)%: battery \(batteryLevel, privacy: .public)%, held at \(band.limit, privacy: .public)%, resumes below \(resume, privacy: .public)%, limit \(limit, privacy: .public)%")
        } else {
            driftMonitor = ChargeHoldDriftMonitor()
            nudgeMonitor = ChargeResumeNudgeMonitor()
            logger.notice("Sailing: the held firmware band is released: battery \(batteryLevel, privacy: .public)%, resumes below \(resume, privacy: .public)%, limit \(limit, privacy: .public)%")
        }
    }

    /// Says so when an override starts or stops being left out of the firmware band's limit.
    /// On a change only, at notice: debug lines are absent from customer logs.
    private func noteOverrideLeftOutOfFirmwareBand(_ override: UserTempChargingMode?) {
        guard override != overrideLeftOutOfFirmwareBand else { return }
        overrideLeftOutOfFirmwareBand = override
        if let override {
            logger.notice("The \(override.limit, privacy: .public)% override is below what the firmware band can hold; the band stays as it is without it")
        } else {
            logger.notice("The firmware band no longer leaves an override out")
        }
    }

    /// Forgets sailing's phase, saying so only where there was one — so with sailing off this
    /// logs nothing.
    private func forgetSailingPhase(because reason: String) {
        guard sailingTracker.phase != nil else { return }
        sailingTracker.forget()
        logger.notice("Sailing: phase forgotten because \(reason, privacy: .public)")
    }

    /// Says so when a sailing hold starts or stops keeping a value other than the person's
    /// limit, and resets the drift and nudge monitors on both edges, as the hot-battery hold's
    /// edges do: each times a run against the limit in force, and that limit has just moved.
    /// With sailing off it is never in force, so this logs nothing.
    private func noteSailingFreezeChange(isInForce: Bool, limit: Int?) {
        guard isInForce != sailingFreezeWasInForce else { return }
        sailingFreezeWasInForce = isInForce
        driftMonitor = ChargeHoldDriftMonitor()
        nudgeMonitor = ChargeResumeNudgeMonitor()
        if isInForce, let limit {
            logger.notice("Sailing: holding by keeping the charge limit at \(limit, privacy: .public)% until the next charge")
        } else {
            logger.notice("Sailing: the kept charge limit is released")
        }
    }

    /// Advances the hot-battery hold for this pass and says so when it starts or ends.
    ///
    /// The backend is only asked for where the answer can matter — the setting on, or a hold
    /// already in force that may need ending — and is cached after the first answer anyway.
    /// An unresolved backend holds nothing, which leaves the hot arm in `updateStatus` on its
    /// existing path: it inhibits, as it always has before the backend is known.
    ///
    /// Both edges reset the drift and nudge monitors. Each times a run against the limit in
    /// force, and that limit has just moved: a run started against the user's limit is no
    /// evidence about the frozen one, and the reverse.
    private func updateHotBatteryHold(
        isEnabled: Bool,
        temperature: Double?,
        chargerConnected: Bool,
        batteryLevel: Int
    ) async {
        let backend = isEnabled || hotBatteryHoldLimit != nil ? await chargeBackend() : nil
        let previous = hotBatteryHoldLimit
        hotBatteryHoldLimit = HotBatteryHold.next(
            frozenAt: previous,
            isEnabled: isEnabled,
            temperature: temperature,
            threshold: Constant.batteryTemperatureWarning,
            chargerConnected: chargerConnected,
            batteryLevel: batteryLevel,
            backend: backend
        )
        guard previous != hotBatteryHoldLimit else { return }
        driftMonitor = ChargeHoldDriftMonitor()
        nudgeMonitor = ChargeResumeNudgeMonitor()
        let reading = temperature.map { String(format: "%.1f °C", $0) } ?? "no reading"
        if let frozen = hotBatteryHoldLimit {
            logger.notice("Battery is hot (\(reading, privacy: .public)) at \(batteryLevel, privacy: .public)%; holding it by setting the charge limit to \(frozen, privacy: .public)% until it cools")
            await analytics.addBreadcrumb(
                category: .chargingManager,
                message: "Battery is hot at \(batteryLevel)%; holding it with a \(frozen)% charge limit"
            )
        } else {
            logger.notice("Hot-battery hold ended (\(reading, privacy: .public), charger connected \(chargerConnected, privacy: .public), setting on \(isEnabled, privacy: .public)); the usual limit applies again")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Hot-battery hold ended")
        }
    }

    /// Whether the override in force is a manual inhibit held by freezing Apple's limit this
    /// pass, and says so when that starts or ends.
    ///
    /// Both edges reset the drift and nudge monitors, as the hot-battery hold's do, and for
    /// the same reason: each times a run against the limit in force, and that limit has just
    /// moved. A run started against the user's limit is no evidence about the frozen one,
    /// and the reverse.
    private func updateManualInhibitHold(
        userTempChargingMode: UserTempChargingMode?,
        batteryLevel: Int
    ) async -> Bool {
        let backend = userTempChargingMode?.isInhibit == true ? await chargeBackend() : nil
        let isHeld = ManualInhibit.isHeldByFrozenLimit(userTempChargingMode, backend: backend)
        guard isHeld != manualInhibitWasHeld else { return isHeld }
        manualInhibitWasHeld = isHeld
        driftMonitor = ChargeHoldDriftMonitor()
        nudgeMonitor = ChargeResumeNudgeMonitor()
        if isHeld, let limit = userTempChargingMode?.limit {
            logger.notice("Inhibit charging: holding the charge limit at \(limit, privacy: .public)% with the battery at \(batteryLevel, privacy: .public)%")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibiting charging by holding the charge limit at \(limit)%")
        } else if let hotLimit = hotBatteryHoldLimit {
            // Advanced before this on every pass, so this is the hold in force now.
            logger.notice("Inhibit charging ended; the hot battery's \(hotLimit, privacy: .public)% limit still holds")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging by a held charge limit ended")
        } else {
            logger.notice("Inhibit charging ended; the usual limit applies again")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging by a held charge limit ended")
        }
        return isHeld
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

    /// What macOS is doing to a battery that sits **above** the limit.
    ///
    /// Three states, not one, and the level tells none of them apart: macOS charging past the
    /// limit, macOS draining back down to it, and the battery simply sitting there with nothing
    /// flowing. All three are `.inhibit` — BatFi issues no write for any of them and cannot stop
    /// any of them — so the only thing that separates them is which way charge is moving.
    ///
    /// Resolved here, in one place, off one SMC reading, because the answers have to agree.
    /// Neither returned flag is the negation of the other: each names its own direction, so the
    /// third state is claimed by neither instead of falling to whichever one tested for an
    /// absence. That absence test is what reported a full battery resting on the charger as a
    /// discharge, while `ChargeHoldDrift` — on this very pass — was logging that the limit was
    /// not holding.
    ///
    /// The backend question is asked first and on its own, so the SMC round trip below is
    /// never reached on a mechanism BatFi drives itself, where a battery above the limit is
    /// BatFi's own inhibit holding and neither state can arise.
    ///
    /// The returned `isDraining`/`isToppingUp` are what the label shows, and pass through
    /// `topUpLatch`: once a top-up has genuinely begun it is kept across the plateau's outward
    /// bursts. The `snapshot` pair is the reading's own answer, for the drift check.
    ///
    /// While a frozen limit is in force — a hot battery's, or a manual inhibit's — neither
    /// label is returned and the latch is kept empty. The limit has just been lowered under a
    /// battery that is still charging, and powerd takes up to 45 s to adopt it, so the first
    /// passes read exactly like macOS charging past the limit — which latched would say
    /// "macOS is calibrating the battery" for minutes over a battery being held, and would outlast
    /// the hold. The drain after a rounded-down freeze would read "Discharging to the limit"
    /// against a limit the menu names as the user's. Both are BatFi's own doing, so the menu
    /// says what an inhibit says on every backend: charging is inhibited. The snapshot pair
    /// still goes to the drift check, which needs it to tell those states from a fault.
    private func systemChargeAboveLimit(
        powerState: PowerState,
        chargerConnected: Bool,
        limitInForce: Int,
        frozenLimitIsInForce: Bool
    ) async -> (isDraining: Bool, isToppingUp: Bool, snapshotIsDraining: Bool, snapshotIsToppingUp: Bool) {
        let drainsItself = await systemDischargesToLimitItself()
        guard drainsItself, powerState.batteryLevel > limitInForce else {
            // Fed to the latch rather than returned straight away, so that a latched top-up
            // that ends at the limit is let go — and logged — like any other.
            let verdict = topUpLatch.record(
                chargerConnected: chargerConnected,
                batteryLevel: powerState.batteryLevel,
                limitInForce: limitInForce,
                isCharging: powerState.isCharging,
                batteryPower: nil,
                mechanismDrainsToLimitItself: drainsItself,
                at: date.now
            )
            await logSystemChargeTransitions(verdict: verdict, powerState: powerState, limitInForce: limitInForce, batteryPower: nil)
            return (false, false, false, false)
        }

        // Asked unconditionally, including when IOKit is asserting a charge. `PowerState`
        // carries no amperage, so the SMC's signed reading is the only thing that can tell the
        // three states apart — and `isCharging` is precisely the reading that needs checking,
        // not the one that excuses the check.
        //
        // It was bounded to `!powerState.isCharging` and that bound is what shipped the bug:
        // this pass runs off `powerSourceChanges()`, so a stale `isCharging` persists until
        // powerd posts the next one. Measured 2026-09-16, that was 43 seconds — the limit
        // lowered under a resting battery at 12:48:53, macOS draining 11 ms later, and IOKit
        // not correcting itself until 12:49:36. For all of it the reading that said so was one
        // round trip away and never taken, while the menu drew that same 9.0 W from
        // `powerInfoChanges` under a label calling it a charge to 100%.
        //
        // Cheap, and already being paid: `powerInfoChanges` polls this at 1 Hz for the menu,
        // and the guard above means it is only reached on a battery above the limit on a
        // mechanism that drains to it itself.
        let batteryPower = (try? await powerDistributionClient.powerInfo())?.batteryPower

        if frozenLimitIsInForce {
            topUpLatch.reset()
            let snapshotIsToppingUp = SystemChargeTopUp.isUnderway(
                batteryLevel: powerState.batteryLevel,
                limitInForce: limitInForce,
                isCharging: powerState.isCharging,
                batteryPower: batteryPower,
                mechanismDrainsToLimitItself: true
            )
            let snapshotIsDraining = SystemChargeDrain.isUnderway(
                batteryLevel: powerState.batteryLevel,
                limitInForce: limitInForce,
                isCharging: powerState.isCharging,
                batteryPower: batteryPower,
                mechanismDrainsToLimitItself: true
            )
            return (false, false, snapshotIsDraining, snapshotIsToppingUp)
        }

        let verdict = topUpLatch.record(
            chargerConnected: chargerConnected,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            isCharging: powerState.isCharging,
            batteryPower: batteryPower,
            mechanismDrainsToLimitItself: true,
            at: date.now
        )
        await logSystemChargeTransitions(verdict: verdict, powerState: powerState, limitInForce: limitInForce, batteryPower: batteryPower)
        return (verdict.isDraining, verdict.isToppingUp, verdict.snapshotIsDraining, verdict.snapshotIsToppingUp)
    }

    private func logSystemChargeTransitions(
        verdict: SystemChargeTopUpLatch.Verdict,
        powerState: PowerState,
        limitInForce: Int,
        batteryPower: Float?
    ) async {
        // Logged on the transition only, and against the published flags rather than a private
        // copy, for the reason the hold's twin below gives. This is the line that says whether
        // a support log's hour of re-applied limits was Apple calibrating or a limit that had
        // genuinely stopped holding — the two produce identical readings otherwise.
        //
        // The SMC reading and IOKit's flag go on every line, because they are what the
        // decision was made from: without them a support log cannot tell a real drain from an
        // outward burst on the calibration plateau (MPX-43), or a stale `isCharging` from a
        // real charge. Notice level, because debug lines are absent from customer logs.
        let published = await appChargingState.currentAppChargingMode()
        let power = batteryPower.map { String(format: "%.1f W", $0) } ?? "not read"
        let isCharging = powerState.isCharging
        let level = powerState.batteryLevel
        if verdict.isToppingUp, !published.systemIsChargingPastLimit {
            logger.notice("macOS is charging past the limit: battery \(level, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, battery power \(power, privacy: .public), charging \(isCharging, privacy: .public). Apple's charge limit does this to keep its state-of-charge estimate accurate; BatFi's limit stays in force and there is no write that stops it.")
            await analytics.addBreadcrumb(
                category: .chargingManager,
                message: "System is charging past the limit at \(level)% against \(limitInForce)%"
            )
        } else if !verdict.isToppingUp, published.systemIsChargingPastLimit {
            let reason = verdict.release.map { "\($0)" } ?? "the reading no longer shows it"
            logger.notice("macOS is no longer charging past the limit (\(reason, privacy: .public)): battery \(level, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, battery power \(power, privacy: .public), charging \(isCharging, privacy: .public)")
        }

        if verdict.isDraining, !published.systemIsDischargingToLimit {
            logger.notice("macOS is draining the battery to the limit: battery \(level, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, battery power \(power, privacy: .public), charging \(isCharging, privacy: .public)")
        } else if !verdict.isDraining, published.systemIsDischargingToLimit {
            logger.notice("macOS is no longer draining the battery to the limit: battery \(level, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, battery power \(power, privacy: .public), charging \(isCharging, privacy: .public)")
        }
    }

    /// Publishes the mode a change of the limit will put the battery in, before the apply, where
    /// `ChargingAheadOfApply.modeAhead` says so; returns whether it did. The mode decision
    /// after the apply settles it as usual.
    private func publishModeAheadOfApply(
        powerState: PowerState,
        chargerConnected: Bool,
        requestedLimit: Int,
        overrideOfThisPass: UserTempChargingMode?,
        sailingResumeLevel: Int?
    ) async -> Bool {
        // The common pass, with the request where the last apply left it, asks nothing more.
        guard let lastApplied = limitRaiseWindow.lastAppliedLimit, requestedLimit != lastApplied else { return false }
        let published = await appChargingState.currentAppChargingMode()
        let ahead = ChargingAheadOfApply.modeAhead(
            backend: await chargeBackend(),
            chargerConnected: chargerConnected,
            lastApplied: lastApplied,
            requested: requestedLimit,
            floor: applyFloor,
            batteryLevel: powerState.batteryLevel,
            overrideInForce: published.userTempOverride,
            passIsStale: overrideOfThisPass != published.userTempOverride,
            appliesAreFailing: lastReportedChargeLimitFailure != nil
        )
        switch ahead {
        case .charging:
            logger.notice("Charge limit raised from \(lastApplied, privacy: .public)% to \(requestedLimit, privacy: .public)% over a battery at \(powerState.batteryLevel, privacy: .public)%; charging ahead of the apply")
            await turnOnCharging(chargerConnected: chargerConnected, currentMode: published.mode)
            return true
        case .inhibit:
            logger.notice("Charge limit lowered from \(lastApplied, privacy: .public)% to \(requestedLimit, privacy: .public)% under a battery at \(powerState.batteryLevel, privacy: .public)%; holding ahead of the apply")
            // After "Resume Discharging" the drain published at the click is kept: macOS drains
            // to the lowered limit once powerd adopts it (`DischargeResumeHold`).
            await inhibitCharging(
                chargerConnected: chargerConnected,
                currentMode: published.mode,
                systemIsDischargingToLimit: dischargeResumeHold.holdsDrain(
                    batteryLevel: powerState.batteryLevel,
                    limitInForce: ChargingAheadOfApply.willApply(requested: requestedLimit, floor: applyFloor),
                    overrideInForce: published.userTempOverride
                ),
                // A sailing hold beginning inside the range is shown as the hold from the
                // start, not as a plain inhibit the pass then renames. Nil with sailing off.
                sailingResumeLevel: sailingResumeLevel
            )
            return true
        default:
            return false
        }
    }

    /// Whether the firmware's band is holding charge on a battery below the limit —
    /// `FirmwareRangeHold`.
    ///
    /// The backend and the band are asked first, so the SMC power read — an XPC round trip —
    /// is only made under `.firmwareRange` with the battery inside the band. A helper that
    /// cannot answer leaves the reading nil, which the rule reads as no hold.
    ///
    /// `resumeLevel` is the one the band was handed with this pass, nil for today's band.
    private func firmwareRangeIsHoldingCharge(
        powerState: PowerState,
        chargerConnected: Bool,
        limitInForce: Int,
        resumeLevel: Int?,
        currentMode: ChargingMode
    ) async -> Bool {
        let backend = await chargeBackend()
        guard backend == .firmwareRange, chargerConnected,
              FirmwareRangeHold.isInsideBand(
                  batteryLevel: powerState.batteryLevel,
                  limitInForce: limitInForce,
                  resumeLevel: resumeLevel
              )
        else { return false }
        let batteryPower = (try? await powerDistributionClient.powerInfo())?.batteryPower
        let isHolding = FirmwareRangeHold.isHolding(
            backend: backend,
            chargerConnected: chargerConnected,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            batteryPower: batteryPower,
            batFiIsDischarging: currentMode == .forceDischarge,
            resumeLevel: resumeLevel
        )
        // On the transition into the drift only, judged against the mode this pass started
        // from. Notice level, because debug lines are absent from customer logs, and with the
        // reading the decision was made from.
        if isHolding, currentMode != .inhibit {
            let power = batteryPower.map { String(format: "%.1f W", $0) } ?? "not read"
            logger.notice("The firmware charge range is holding charge: battery \(powerState.batteryLevel, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, battery power \(power, privacy: .public), charging \(powerState.isCharging, privacy: .public)")
        }
        return isHolding
    }

    /// Whether the firmware is holding a sailing band under a temporary limit, for the override
    /// arm, which otherwise reads every level below the limit as charging. Only with a band
    /// resume level, so with sailing off — or on any other backend — it asks nothing and
    /// answers false, leaving that arm exactly as it was.
    private func firmwareSailingBandIsHolding(
        bandResumeLevel: Int?,
        powerState: PowerState,
        chargerConnected: Bool,
        limitInForce: Int,
        currentMode: ChargingMode
    ) async -> Bool {
        guard let bandResumeLevel, powerState.batteryLevel < limitInForce else { return false }
        return await firmwareRangeIsHoldingCharge(
            powerState: powerState,
            chargerConnected: chargerConnected,
            limitInForce: limitInForce,
            resumeLevel: bandResumeLevel,
            currentMode: currentMode
        )
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
        enforcedLimit: Int?,
        holdVerdictIsHeldBack: Bool,
        currentMode: ChargingMode
    ) async -> Bool {
        guard await systemDischargesToLimitItself() else { return false }
        // A raise powerd has not adopted, or adopted too recently for charge to be seen going
        // in (`ChargeLimitRaiseWindow`): no verdict, and no attribution asked for one. Logged
        // as the end of a hold if one was published, like any other.
        guard !holdVerdictIsHeldBack else {
            if await appChargingState.currentAppChargingMode().systemIsHoldingBelowLimit {
                logger.notice("macOS is no longer holding charge below the limit: the limit was raised to \(limitInForce, privacy: .public)% and powerd enforces \(enforcedLimit.map(String.init) ?? "no policy", privacy: .public); battery \(powerState.batteryLevel, privacy: .public)%, charging \(powerState.isCharging, privacy: .public)")
            }
            return false
        }
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
            mechanismOwnsChargingDecision: true,
            enforcedLimit: enforcedLimit
        )
        var chargeIsFlowingIn: Bool?
        if iokitSaysHeld {
            // Negative `batteryPower` is the battery as a *target* rather than a source — the
            // sign convention `PowerGraph` renders — and only past the resting band is it a
            // charge (`ChargeDirection.chargeIsFlowingIn`): a held battery rests at about 0 W
            // and dips a fraction of a watt into the pack several times a minute, which ended
            // the hold for a pass each time. The 46 W the SMC caught ahead of IOKit clears the
            // band by a wide margin. A helper that cannot answer leaves this nil, so an
            // unreachable helper cannot turn a hold into a phantom charge.
            chargeIsFlowingIn = ChargeDirection.chargeIsFlowingIn(
                batteryPower: (try? await powerDistributionClient.powerInfo())?.batteryPower
            )
        }
        let isHolding = SystemChargeHold.isHoldingBelowLimit(
            chargerConnected: chargerConnected,
            isCharging: powerState.isCharging,
            batteryLevel: powerState.batteryLevel,
            limitInForce: limitInForce,
            holdIsAttributed: holdIsAttributed,
            chargeIsFlowingIn: chargeIsFlowingIn,
            batFiIsDischarging: currentMode == .forceDischarge,
            mechanismOwnsChargingDecision: true,
            enforcedLimit: enforcedLimit
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
            logger.error("macOS is holding charge below the limit: battery \(powerState.batteryLevel, privacy: .public)%, limit in force \(limitInForce, privacy: .public)%, powerd enforces \(enforcedLimit.map(String.init) ?? "no policy", privacy: .public), firmware attributes the hold to its own limit. BatFi has no write that can resume charging.")
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
    ///
    /// With `resumeLevel` — sailing in play where the firmware holds the band — the limit goes
    /// out with it through the range call, on every pass, so the helper's needs-write key stays
    /// the same from pass to pass. Without it, the one-value call exactly as before sailing.
    /// Which call actually went out is recorded in `firmwareBandHandover`; a failed call
    /// records nothing, leaving what the helper was last told.
    @discardableResult
    private func applyChargeLimit(_ limit: Int, resumeLevel: Int?) async -> Int? {
        do {
            let applied: Int
            if let resumeLevel {
                let range = try await chargingClient.applyChargeRange(limit, resumeLevel)
                applied = range.limit
                firmwareBandHandover.record(limit: limit, resumeLevel: resumeLevel, call: range.call)
            } else {
                applied = try await chargingClient.applyChargeLimit(limit)
                firmwareBandHandover.record(limit: limit, resumeLevel: nil, call: .limitOnly)
            }
            lastReportedChargeLimitFailure = nil
            applyFloor = ChargingAheadOfApply.learnedFloor(previous: applyFloor, requested: limit, applied: applied)
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
        await appChargingState.setSystemChargeHold(false, false, false)
        // Nor is it holding anything for sailing.
        await appChargingState.setSailingHold(nil)
        // And a top-up latched before charge management was turned off must not be resumed
        // when it is turned back on.
        topUpLatch.reset()
        // Same reasoning for the charge-to-full hold: it *is* a limit of 100 that BatFi keeps
        // requesting, and there is no request left to make. Published as well as cleared, so
        // the label goes with it.
        holdingFullChargeUntilUnplugged = ChargeToFullHold.next(
            holding: holdingFullChargeUntilUnplugged,
            event: .chargingHandedBack
        )
        await appChargingState.setHoldingFullChargeUntilUnplugged(false)
        // And a hot battery's frozen limit, for the same reason — and so that re-engaging
        // later, perhaps hours later, never applies a value frozen before this.
        hotBatteryHoldLimit = nil
        // Sailing's kept limit likewise: the helper has handed charging back to macOS.
        sailingLimitHold = SailingLimitHold()
        sailingFreezeWasInForce = false
        // And the firmware's held band, which the release has just taken out of force.
        firmwareSailingHold = FirmwareSailingHold()
        lastFirmwareSailingBand = nil
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
        if batFiHoldsSystemSleepDisable {
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

    /// Whether BatFi currently holds the system-wide sleep disable.
    ///
    /// This used to be a guess — `allowDischargingFullBattery || disableSleepDuringDischarging`,
    /// the settings that can *take* the flag — and the guess is what issue #148 was. Those
    /// release sites sit on the ordinary charging path, so with one of the settings merely
    /// switched **on** every pass wrote `pmset -a disablesleep 0`, whether or not BatFi had
    /// disabled anything. A `SleepDisabled` the user had set by hand went down with it,
    /// within minutes, over and over, with no BatFi feature running that would explain it.
    ///
    /// The record replaces the guess: this is `true` only where BatFi actually wrote the
    /// flag, so every future taker is covered without being listed and nothing else's flag
    /// is ever touched. It is also still a gate rather than a bare `true`, and the reason is
    /// unchanged — `disableSleep(false)` makes an XPC call, and this runs on every status
    /// update.
    ///
    /// Persisted, because the flag it tracks outlives the process: see the key's own note.
    private var batFiHoldsSystemSleepDisable: Bool {
        defaults.value(.systemSleepDisabledByBatFi)
    }

    /// How long to let the adapter come back before sleep is allowed again.
    ///
    /// The charge command is issued first and returns immediately, but the adapter does not
    /// reappear the instant `CHIE` comes off — `ExternalConnected` stays false for a moment
    /// afterwards. Re-enabling sleep inside that window puts the Mac back on the very footing
    /// the disable existed to prevent, and a closed lid sleeps it: measured on 26A5416b,
    /// stopping "Run on Battery" with the lid shut still slept the machine.
    private static let sleepRestoreDelayAfterDischarge: Duration = .seconds(2)

    /// Puts sleep back once charging has actually resumed.
    ///
    /// The wait is unconditional because both callers already are: they reach this only
    /// where BatFi holds the flag, which is exactly the case that has an adapter to wait
    /// for. It used to re-check that here, back when the callers asked a broader question
    /// and an ordinary pass could arrive with nothing held.
    private func restoreSleepAfterDischarge() async {
        try? await clock.sleep(for: Self.sleepRestoreDelayAfterDischarge)
        await setSleepDisabled(false)
    }

    /// Takes back a system sleep disable an earlier BatFi left up, once.
    ///
    /// Versions before `systemSleepDisabledByBatFi` re-enabled sleep on the next charging
    /// pass whether or not it was theirs to re-enable, which is the bug — but it also meant
    /// a process that died mid-discharge healed itself on the next launch. The record ends
    /// both, so the healing is done deliberately here instead, and exactly once.
    private func adoptSleepDisableLeftByAnEarlierVersionIfNeeded() async {
        guard !defaults.value(.didCheckForSleepDisableLeftByAnEarlierVersion) else { return }
        let systemAlreadyDisabled = await sleepAssertionClient.systemSleepIsDisabled()
        // Nothing recorded where the helper could not answer — during onboarding, say, or
        // while it is being reclaimed. Spending the one look on a "don't know" would leave
        // a genuinely stranded flag stranded for good.
        guard systemAlreadyDisabled != nil else { return }
        defaults.setValue(.didCheckForSleepDisableLeftByAnEarlierVersion, value: true)
        guard SystemSleepDisableOwnership.adoptsFlagLeftByAnEarlierVersion(
            systemAlreadyDisabled: systemAlreadyDisabled,
            disableSleepDuringDischarging: defaults.value(.disableSleepDuringDischarging)
        ) else { return }
        logger.notice("Adopting the system sleep disable an earlier version left up")
        defaults.setValue(.systemSleepDisabledByBatFi, value: true)
    }

    /// The single writer, so the record cannot drift from what was actually written.
    ///
    /// `SleepDisabled` is one global flag with several possible owners, so the decision of
    /// whether this write may go out at all belongs to `SystemSleepDisableOwnership` — the
    /// short version being that BatFi takes down only what BatFi put up.
    private func setSleepDisabled(_ disabled: Bool) async {
        let holdsIt = batFiHoldsSystemSleepDisable
        // Asked only where the answer can change anything, which is a fresh take. A release
        // BatFi does not own is refused whatever the live value says, and a re-assert of a
        // flag it already holds goes out either way — neither is worth an XPC round trip on
        // a path that runs on every status update.
        let systemAlreadyDisabled = disabled && !holdsIt
            ? await sleepAssertionClient.systemSleepIsDisabled()
            : nil
        let decision = SystemSleepDisableOwnership.decide(
            disable: disabled,
            batFiHoldsIt: holdsIt,
            systemAlreadyDisabled: systemAlreadyDisabled
        )
        guard decision.writes else {
            logger.debug("Leaving the system sleep flag alone; BatFi does not own it")
            return
        }
        // Claimed before the write and released only after one that succeeded. Both point
        // the same way on purpose: a process that dies mid-call is remembered as holding a
        // flag it may not have set, which costs one redundant `0`, rather than forgetting
        // one it did set, which costs a Mac that never sleeps again.
        if decision.batFiHoldsIt, !holdsIt {
            defaults.setValue(.systemSleepDisabledByBatFi, value: true)
        }
        do {
            try await sleepAssertionClient.disableSleep(disabled)
            if holdsIt, !decision.batFiHoldsIt {
                defaults.setValue(.systemSleepDisabledByBatFi, value: false)
            }
        } catch {
            logger.warning("Could not set the system sleep flag: \(error, privacy: .public)")
        }
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
        await appChargingState.setSystemChargeHold(false, false, false)
        // Nor holding for sailing — but not cleared here: a hold cleared ahead of the command
        // reads as the plain inhibit ("Inhibiting charging") for the whole round trip to the
        // helper. It goes with the mode, in one publish, where the command goes out; where it
        // is skipped as already in force, the mode is charging and the level is not read.
        guard shouldApply(.charging, currentMode: currentMode) else {
            await appChargingState.setSailingHold(nil)
            return
        }
        logger.debug("Turning on charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on charging")
        do {
            try await chargingClient.turnOnAutoChargingMode()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Charging turned on")
            didApply()
            await appChargingState.updateChargingModeEndingSailingHold(.charging)
            // Last, and after a pause — see `restoreSleepAfterDischarge`. Ahead of the mode
            // update it also delayed the menu by the length of that pause.
            if batFiHoldsSystemSleepDisable {
                await restoreSleepAfterDischarge()
            }
        } catch {
            logger.warning("Failed to turn on charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on charging. Error: \(error.localizedDescription)")
            // The pass decided to charge, so sailing no longer holds: what stays in force is
            // an inhibit the resume failed to lift, told as one, as it is with sailing off.
            await appChargingState.setSailingHold(nil)
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
    ///   - sailingResumeLevel: the level below which charging resumes, where this inhibit is
    ///     sailing's hold; nil for every other inhibit, which clears a hold published earlier.
    /// - Returns: whether the inhibit is in force: written now, or already in force and not
    ///   due to be re-sent. False only when the write failed.
    @discardableResult
    private func inhibitCharging(
        chargerConnected: Bool,
        currentMode: ChargingMode,
        systemIsDischargingToLimit: Bool = false,
        systemIsHoldingBelowLimit: Bool = false,
        systemIsChargingPastLimit: Bool = false,
        sailingResumeLevel: Int? = nil
    ) async -> Bool {
        await updateChargerConnected(chargerConnected)
        // Beside `updateChargerConnected` and above the guard, deliberately. This reports
        // what is true right now rather than what BatFi just wrote, and it goes on changing
        // while the mode does not: a 61% battery draining to a 55% limit is `.inhibit` for
        // the whole descent and `.inhibit` again when it settles. Below the guard it would
        // only ever be refreshed on the passes that actually send a command, so the label
        // would latch at whichever value was true when the mode last changed.
        await appChargingState.setSystemChargeHold(
            systemIsDischargingToLimit,
            systemIsHoldingBelowLimit,
            systemIsChargingPastLimit
        )
        // Above the guard for the same reason: the hold is published on every pass, while the
        // command goes out only when it is due.
        await appChargingState.setSailingHold(sailingResumeLevel)
        guard shouldApply(.inhibit, currentMode: currentMode) else {
            // Already inhibiting and nothing has happened that could have undone it. The
            // pulling task is not restarted here: it was started when this mode was entered
            // and is still running.
            return true
        }
        logger.debug("Inhibiting charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibiting charging")
        do {
            try await chargingClient.inhibitCharging()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging turned on")
            didApply()
            await appChargingState.updateChargingMode(.inhibit)
            await startPullingPowerStateIfNeeded()
            if batFiHoldsSystemSleepDisable {
                await restoreSleepAfterDischarge()
            }
            return true
        } catch {
            logger.warning("Failed to inhibit charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to inhibit charging. Error: \(error.localizedDescription)")
            return false
        }
    }

    private func turnOnDischarging(chargerConnected: Bool, disableSleep: Bool, currentMode: ChargingMode) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        // BatFi's own discharge, which `.forceDischarge` already names. The system's drain
        // and this one are mutually exclusive by construction — `updateStatus` skips its
        // discharge arm entirely on a mechanism that drains itself — so this can only ever
        // be clearing a value left by an earlier pass.
        await appChargingState.setSystemChargeHold(false, false, false)
        // A discharge is not sailing's hold either. Cleared with the mode where the command
        // goes out, as in `turnOnCharging`, so the hand-over never reads as the plain inhibit;
        // on every other way out, here.
        // Ahead of the assertion, not after it. Taking the assertion first and then
        // returning through this guard stranded it: nothing below runs, and every release
        // site is on a path this pass no longer reaches.
        guard chargerConnected else {
            await appChargingState.setSailingHold(nil)
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
            // happens when the discharge ends, through `batFiHoldsSystemSleepDisable`.
            if !disableSleep {
                await setSleepDisabled(false)
            }
            return
        }
        // One call, not a `false` immediately followed by a `true`. Both reach the same
        // global flag, so the pair used to release it and take it straight back on every
        // pass of a discharge with the setting on — two writes and, now, a needless handover
        // of ownership.
        await setSleepDisabled(disableSleep || defaults.value(.disableSleepDuringDischarging))
        // Below the sleep assertions on purpose. Those follow `disableSleep`, which the user
        // can change while the discharge is already running, so they are not the mode's to
        // skip — only the charging command itself is.
        guard shouldApply(.forceDischarge, currentMode: currentMode) else {
            await appChargingState.setSailingHold(nil)
            return
        }
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on discharging")
        logger.debug("Turning on discharging")
        do {
            try await chargingClient.forceDischarge()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Discharging turned on")
            didApply()
            await appChargingState.updateChargingModeEndingSailingHold(.forceDischarge)

        } catch {
            logger.warning("Failed to turn on discharging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on discharging. Error: \(error.localizedDescription)")
            await appChargingState.setSailingHold(nil)
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
            let chargerConnected = ChargerConnection.isConnected(
                reported: powerState.chargerConnected,
                isDerived: powerState.chargerConnectionIsDerived,
                appMode: mode
            )
            // Read last, right before the publish: a pass suspended in the apply may have
            // published this connection ahead of its mode, and this read must not clear that.
            let published = await appChargingState.currentAppChargingMode()
            await appChargingState.setAppChargingMode(
                .init(
                    mode: mode,
                    userTempOverride: userTempOverride,
                    chargerConnected: chargerConnected,
                    // Stated rather than inherited: this is built from the *helper's* status
                    // read, which carries no answer about the drain, and the paths that
                    // reach it — a wake, a display change, the first mode of the session —
                    // are exactly the ones where an earlier answer should not be trusted.
                    // `updateStatusWithCurrentState()` on the next line re-derives it from
                    // the current battery level and limit.
                    systemIsDischargingToLimit: false,
                    systemIsHoldingBelowLimit: false,
                    isAwaitingModeForChargerChange: ChargerConnection.isAwaitingModeAfterFetch(
                        published: published,
                        fetchedConnected: chargerConnected
                    ),
                    // Carried over an inhibit, unlike the flags above: the hold is BatFi's own
                    // decision, not something the helper could have answered, and dropping it
                    // here would show "Inhibiting charging" until the pass below names the hold
                    // again — or clears it, if that pass decides otherwise.
                    sailingResumeLevel: mode == .inhibit ? published.sailingResumeLevel : nil
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
                // ...and it is the end condition of a charge-to-full hold. Only the edge to
                // *disconnected* is an event: a connect has nothing to undo, because the hold
                // was cleared when the charger came out. The value is the resolved
                // `ChargerConnection.isConnected`, so a derived "Battery Power" during a BatFi
                // discharge is not mistaken for an unplug — and no discharge runs while the
                // hold is on, which is the point of it.
                if !chargerConnected {
                    let wasHolding = holdingFullChargeUntilUnplugged
                    holdingFullChargeUntilUnplugged = ChargeToFullHold.next(
                        holding: holdingFullChargeUntilUnplugged,
                        event: .chargerDisconnected
                    )
                    if wasHolding {
                        logger.notice("Charger unplugged; the charge-to-full hold is over and the limit applies again")
                    }
                }
                self.lastChargerConnectedStatus = newState
            }
        } else {
            self.lastChargerConnectedStatus = newState
        }
    }

    private var removeTempOverrideTask: Task<Void, Never>?

    /// What the world looked like when the override now in force was armed.
    private struct TempOverrideArm {
        let override: UserTempChargingMode
        let armedAt: Date
        let batteryLevel: Int
    }

    /// Keeps `tempOverrideArm` in step with the override, and hands back the arm the
    /// removal rules are to be measured against.
    ///
    /// Every route that sets an override — the menu, the hotkeys, the App Intents,
    /// automation — goes through `appChargingState`, and `updateStatus` runs on every change
    /// it makes, so recognising the change here covers all of them without each having to
    /// remember to stamp anything. The whole override is the identity — its limit and
    /// whether it is an inhibit: an override replaced by a different one is a new arm, even
    /// at the same limit, and the same one on a later pass is not.
    private func noteTempOverrideArm(
        _ userTempChargingMode: UserTempChargingMode?,
        batteryLevel: Int
    ) -> TempOverrideArm? {
        guard let userTempChargingMode else {
            tempOverrideArm = nil
            return nil
        }
        if let arm = tempOverrideArm, arm.override == userTempChargingMode { return arm }
        // A new override replaces the intent a charge-to-full hold came from, so the hold
        // ends here rather than lying in wait to re-assert 100 once the new override is done.
        holdingFullChargeUntilUnplugged = ChargeToFullHold.next(
            holding: holdingFullChargeUntilUnplugged,
            event: .overrideArmed
        )
        let arm = TempOverrideArm(
            override: userTempChargingMode,
            armedAt: date.now,
            batteryLevel: batteryLevel
        )
        tempOverrideArm = arm
        return arm
    }

    private func handleRemovingTempOverrideOnDisconnect(
        chargerConnected: Bool,
        batteryLevel: Int,
        overrideLimit: Int,
        armedAt: Date?,
        overrideIsFrozenInhibit: Bool
    ) {
        let secondsSinceDisconnect: TimeInterval?
        // Whether the override predates the unplug, which is what makes it *left over*
        // rather than a standing request for the next connection. An arm we have no record
        // of is treated as predating: that is the behaviour this rule has always had, and
        // the record is only ever missing before the first status pass has seen the
        // override at all.
        let armedBeforeDisconnect: Bool
        if let disconnectStatus = lastChargerConnectedStatus, !disconnectStatus.isConnected {
            secondsSinceDisconnect = date.now.timeIntervalSince(disconnectStatus.date)
            armedBeforeDisconnect = armedAt.map { $0 <= disconnectStatus.date } ?? true
        } else {
            secondsSinceDisconnect = nil
            armedBeforeDisconnect = true
        }

        switch TempOverrideDisconnectPolicy.decision(
            chargerConnected: chargerConnected,
            batteryLevel: batteryLevel,
            overrideLimit: overrideLimit,
            secondsSinceDisconnect: secondsSinceDisconnect,
            overrideArmedBeforeDisconnect: armedBeforeDisconnect,
            overrideIsFrozenInhibit: overrideIsFrozenInhibit
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
