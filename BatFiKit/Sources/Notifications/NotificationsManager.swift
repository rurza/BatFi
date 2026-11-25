//
//  NotificationsManager.swift
//
//
//  Created by Adam on 17/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Cocoa
import DefaultsKeys
import Dependencies
import L10n
import os
import Shared
import UserNotifications

private let optimizedBatteryChargingCategoryIdentifier = "OPTIMIZED_BATTERY_CHARGING"
private let settingsActionIdentifier = "SETTINGS_ACTION"
/// The prefix of both trial notifications' identifiers (the client adds a unique suffix to each);
/// clicking either opens the licence window.
private let trialNoticeIdentifier = "software.micropixels.BatFi.notifications.trial"

@MainActor
public class NotificationsManager: NSObject {
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.updater) private var updater
    @Dependency(\.defaults) private var defaults
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.date) private var date
    @Dependency(\.userNotificationsClient) var userNotificationsClient
    @Dependency(\.persistence) var persistence
    @Dependency(\.licenseClient) private var licenseClient
    @Dependency(\.sleepClient) private var sleepClient
    private lazy var center = UNUserNotificationCenter.current()
    private lazy var logger = Logger(category: "🔔")
    private var chargingModeTask: Task<Void, Never>?
    /// The last charging state seen and the last sentence posted, which decide whether the
    /// next charging-mode notification is news. The sentence is kept for one charging session:
    /// forgotten on unplug, so each plug-in gets its banner. The first state after observing
    /// starts — a launch, or the setting turned back on — is a baseline and is not posted.
    private var announcements = ModeChangeAnnouncement.Memory()
    private var optimizedBatteryChargingTask: Task<Void, Never>?
    private var lastAlertDate: Date = .distantPast
    private var didShowLowBatteryNotification = false
    /// Whether a running trial unlocks the app; see `showChargingStateModeDidChangeNotification`.
    private let trialIsRunning: @MainActor () -> Bool
    /// What the licence screens show, now and on each change; the trial's notifications follow it.
    private let licenceScreenChanges: @MainActor () -> AsyncStream<LicenceScreen>
    private let openLicenceWindow: @MainActor () -> Void
    private var licenceScreen: LicenceScreen = .undetermined
    private var nextTrialNoticeCheck: Task<Void, Never>?
    /// Which waiting check `nextTrialNoticeCheck` is, so a finished one clears only itself.
    private var trialNoticeCheckGeneration = 0

    public init(
        trialIsRunning: @escaping @MainActor () -> Bool,
        licenceScreenChanges: @escaping @MainActor () -> AsyncStream<LicenceScreen>,
        openLicenceWindow: @escaping @MainActor () -> Void
    ) {
        self.trialIsRunning = trialIsRunning
        self.licenceScreenChanges = licenceScreenChanges
        self.openLicenceWindow = openLicenceWindow
        super.init()
        center.delegate = self
        setUpObserving()
    }

    func setUpObserving() {
        Task {
            for await screen in licenceScreenChanges() {
                licenceScreen = screen
                if case .licensed = screen {
                    await removeDeliveredTrialNotices()
                }
                await considerTrialNotices()
            }
        }
        // The waiting check does not follow the clock being changed, and the screen answer does
        // not change with it, so both a clock change and a wake look again.
        Task { [weak self, sleepClient] in
            for await _ in sleepClient.macDidWake() {
                await self?.considerTrialNotices()
            }
        }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSSystemClockDidChange) {
                await self?.considerTrialNotices()
            }
        }
        Task {
            for await showChargingStausChanged in defaults.observe(.showChargingStausChanged) {
                if showChargingStausChanged {
                    startObservingChargingStateMode()
                } else {
                    cancelObservingChargingStateMode()
                }
            }
        }
        Task {
            for await showOptimizedBatteryCharging in defaults.observe(.showOptimizedBatteryCharging) {
                if showOptimizedBatteryCharging {
                    startObservingOptimizedBatteryCharging()
                } else {
                    cancelObservingOptimizedBatteryCharging()
                }
            }
        }

        Task {
            for await (showBatteryLowNotification, powerSourceState, threshold) in combineLatest(
                defaults.observe(.showBatteryLowNotification),
                powerSourceClient.powerSourceChanges(),
                defaults.observe(.batteryLowNotificationThreshold)
            ).debounce(for: .seconds(5)) {
                guard showBatteryLowNotification else {
                    didShowLowBatteryNotification = false
                    continue
                }

                guard !powerSourceState.isCharging else {
                    if powerSourceState.batteryLevel > threshold || powerSourceState.isCharging {
                        didShowLowBatteryNotification = false
                    }
                    continue
                }

                if powerSourceState.batteryLevel <= threshold, !didShowLowBatteryNotification, powerSourceState.batteryLevel != 0 {
                    didShowLowBatteryNotification = true
                    await showBatteryIsLowNotification()
                }
            }
        }
        Task {
            for await (lastChargingReminderDate, showRemindersToDischargeAndChargeBattery, _) in combineLatest(
                    defaults.observe(.lastChargingReminderDate),
                    defaults.observe(.showRemindersToDischargeAndChargeBattery),
                    powerSourceClient.powerSourceChanges()
                    ) {
                guard showRemindersToDischargeAndChargeBattery else { continue }
                guard lastChargingReminderDate < date.now.addingTimeInterval(-60 * 60 * 24 * 3) else { continue }
                guard let values = try? await persistence.fullChargeAndDischargeWasInLast30Days() else { continue }
                guard !values.charge && !values.discharge else {
                    continue
                }
                do {
                    try await showBatteryCalibrationReminder()
                    defaults.setValue(.lastChargingReminderDate, value: date.now)
                } catch { }
            }
        }
    }

    // MARK: - Charging mode

    func startObservingChargingStateMode() {
        // Cancelled before it is replaced, or the old one keeps listening.
        //
        // `defaults.observe` yields the current value on subscribe and again on every write,
        // including a write of the same value, so this runs more than once per launch. The
        // assignment overwrote the reference without stopping the task behind it, leaving two
        // live subscribers to `appChargingModeDidChage()` — and every mode change then posted
        // its notification once per subscriber. Measured 2026-08-26: 13 state changes produced
        // **26** distinct notifications, an exact doubling, which is what the duplicate pairs in
        // Notification Center were. A third emission would have made it three.
        //
        // The identifiers are deliberately unique per notification (see
        // `UserNotificationsClient+Live`), so duplicates stack as separate banners rather than
        // collapsing into one — which is correct for genuine repeat events and merciless here.
        chargingModeTask?.cancel()
        chargingModeTask = Task {
            // Debounced, so a run of changes announces only where it settled.
            //
            // The charging state can move several times in a couple of seconds — a launch
            // settling, a limit being changed, macOS handing the policy back — and each step is
            // a real change with real, *different* text, so the dedupe below cannot collapse
            // them and should not: they are not repeats. But the intermediate states are not
            // worth a banner each; only the one the battery ends up in is.
            //
            // Trailing, which is what `debounce` gives: nothing is posted until 2s of quiet, and
            // then only the latest value. A settled state is announced 2s late, which nobody
            // notices, and a burst is announced once, which is the point. The same operator and
            // the same injected clock as `startObservingOptimizedBatteryCharging`.
            //
            // Kept *alongside* the text dedupe rather than instead of it: debounce collapses
            // bursts, and the dedupe stops an unchanged sentence being repeated after a gap
            // longer than the window, which `combineLatest` re-emissions would otherwise do.
            for await (chargingMode, manageCharging) in combineLatest(
                appChargingState.appChargingModeDidChage(),
                defaults.observe(.manageCharging)
            ).debounce(for: .seconds(2), clock: AnyClock(self.clock)) {
                switch ModeChangeAnnouncement.consideration(of: chargingMode, manageCharging: manageCharging) {
                case .skip:
                    announcements.skip(chargingMode)
                    continue
                case .awaitMode:
                    // A plug-in published ahead of its mode, which on macOS 27 can take up to
                    // 45 s — longer than the debounce. The mode it carries is the one from
                    // before the charger came in, so it is neither posted nor remembered;
                    // the mode the applier derives arrives next and is the one announced.
                    // Or an Inhibit Charging pause that has not taken hold yet: its banner
                    // is the paused state, which arrives next in the same way.
                    logger.debug("Waiting for the mode before announcing")
                    continue
                case .announce:
                    break
                }
                logger.info("Should display notification")
                await showChargingStateModeDidChangeNotification(chargingMode)
            }
        }
    }

    func cancelObservingChargingStateMode() {
        announcements.forget()
        chargingModeTask?.cancel()
    }

    func showChargingStateModeDidChangeNotification(_ mode: AppChargingMode) async {
        // Posted for a stored licence, as before, and for a running trial, which unlocks the
        // app as a licence does.
        if !trialIsRunning() {
            guard (try? await licenseClient.cachedLicense()) != nil else { return }
        }
        if await userNotificationsClient.requestAuthorization() == true {
            do {
                // Automation can override the configured limit. When it's active, show the
                // limit it actually applies and name the responsible rule.
                let automationLimit = await appChargingState.currentAutomationTarget()?.limit
                let effectiveLimit = automationLimit ?? defaults.value(.chargeLimit)
                let chargeLimitFraction = Double(effectiveLimit) / 100
                let automationRuleName = automationLimit != nil
                    ? (activeAutomationRuleName() ?? L10n.Automation.untitledRule)
                    : nil

                // macOS moving between its own sub-states of the held mode — charging to 100%,
                // draining to the limit, holding — is shown on the menu label and not posted.
                // During a calibration plateau it did so every minute or two (MPX-43).
                let seen = ModeChangeAnnouncement.Seen(
                    mode: mode,
                    limit: effectiveLimit,
                    automationRuleName: automationRuleName
                )

                let title = L10n.Notifications.Notification.Subtitle.newMode(mode.stateDescription)
                let body = mode.stateDescription(
                    chargeLimitFraction: chargeLimitFraction,
                    automationRuleName: automationRuleName
                ) ?? ""

                // Deduped on the rendered sentence, and it has to be the sentence.
                //
                // Two things upstream conspire. `combineLatest` emits whenever *either* side
                // does and re-emits the cached value of the other, so a tick of
                // `defaults.observe(.manageCharging)` re-delivers a mode nobody changed. And
                // several distinct `AppChargingMode` values render the *same* text —
                // `stateDescription` returns "Charging to the limit" for `.charging` whatever
                // the system flags say, so a flag flip under an unchanged mode is a different
                // model and an identical notification.
                //
                // Keying on the model was the fix that did not work: measured 2026-08-26,
                // "Charging to the limit / The limit is 85%" arrived twice on launch with the
                // model comparison already in place. The user cannot see the model. What must
                // not repeat is the words, so the words are the key.
                //
                // The state still has to be *re-announceable* later: this remembers only the
                // last thing said, so charging -> discharging -> charging notifies three times,
                // which is correct. And it remembers it for one charging session only: unplugging
                // forgets it, so plugging in again below the limit says "Charging to the limit"
                // again. It suppresses only saying the same thing twice in a row on one plug-in.
                switch announcements.decide(seen, title: title, body: body) {
                case .post:
                    break
                case .baseline:
                    logger.info("Charging mode notification suppressed; the first state since observing started is not a change")
                    return
                case .quietSubStateChange:
                    logger.info("Charging mode notification suppressed; macOS only moved between its own sub-states of the held mode")
                    return
                case .repeatedText:
                    logger.debug("Charging mode notification suppressed; the same text was already posted while plugged in")
                    return
                }

                logger.debug("Adding notification request to the notification center")
                try await userNotificationsClient.showUserNotification(
                    title: title,
                    body: body,
                    identifier: "software.micropixels.BatFi.notifications.mode",
                    threadIdentifier: "Charging mode",
                    delay: 1.5
                )
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Name of the automation rule the engine currently considers active, or nil if none can
    /// be resolved. Empty names fall back to a generic label.
    private func activeAutomationRuleName() -> String? {
        guard let rule = AutomationEngine.activeRule(
            in: defaults.value(.automationRules),
            activeRuleID: defaults.value(.automationActiveRuleID)
        ) else { return nil }
        return rule.name.isEmpty ? L10n.Automation.untitledRule : rule.name
    }

    func showBatteryIsLowNotification() async {
        if await userNotificationsClient.requestAuthorization() == true {
            do {
                logger.debug("Adding notification request to the notification center")
                try await userNotificationsClient.showUserNotification(
                    title: L10n.Notifications.Notification.Title.lowBattery,
                    body: L10n.Notifications.Notification.Body.lowBattery,
                    identifier: "software.micropixels.BatFi.notifications.lowBattery", 
                    threadIdentifier: "Battery low",
                    delay: nil
                )
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func showBatteryCalibrationReminder() async throws {
        if await userNotificationsClient.requestAuthorization() == true {
            do {
                logger.debug("Adding battery calibration notification request to the notification center")
                try await userNotificationsClient.showUserNotification(
                    title: L10n.Notifications.Notification.Title.lowBattery,
                    body: L10n.Notifications.Notification.Body.lowBattery,
                    identifier: "software.micropixels.BatFi.notifications.calibration",
                    threadIdentifier: "Calibration",
                    delay: nil
                )
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    // MARK: - Trial

    /// Sends the trial notification that is due, if any, and arranges to look again when the
    /// next one will be. Only the trial screens have notices (`TrialNotice`), so a key accepted
    /// at any point stops them: nothing is left scheduled with the system, and the check
    /// waiting here is cancelled.
    func considerTrialNotices() async {
        nextTrialNoticeCheck?.cancel()
        nextTrialNoticeCheck = nil
        let seen = defaults.value(.trialSeenRunningUntil)
        let nowSeen = TrialNotice.seenRunningUntil(after: licenceScreen, previous: seen)
        if nowSeen != seen {
            defaults.setValue(.trialSeenRunningUntil, value: nowSeen)
        }
        if decideTrialNotice().due != nil,
           await userNotificationsClient.requestAuthorization() == true {
            // Decided again after the wait for authorisation, and recorded before anything
            // else can run, so a screen change arriving meanwhile cannot send it twice.
            let decision = decideTrialNotice()
            if let due = decision.due, let end = licenceScreen.trialEnd {
                record(due, forEnd: end)
                await showTrialNotice(due)
            }
        }
        // Not authorised: nothing is recorded, and a later change looks again.
        guard let next = decideTrialNotice().next
        else { return }
        let delay = max(0, next.timeIntervalSince(date.now))
        // Another look may have run while this one waited for authorisation and left its own
        // check waiting: this one, decided last, replaces it.
        nextTrialNoticeCheck?.cancel()
        trialNoticeCheckGeneration &+= 1
        let generation = trialNoticeCheckGeneration
        nextTrialNoticeCheck = Task { [weak self] in
            // The continuous clock counts time asleep, so a day-before notice that fell due
            // while the Mac slept is sent on waking.
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            // Forgotten first, or looking again would cancel this very task midway — but only
            // while it is still the waiting check, never one that replaced it.
            guard let self, !Task.isCancelled, self.trialNoticeCheckGeneration == generation else { return }
            self.nextTrialNoticeCheck = nil
            await self.considerTrialNotices()
        }
    }

    /// A key was accepted: a trial notice still in Notification Center no longer applies.
    /// Nothing is ever scheduled with the system, so only delivered ones can be left.
    private func removeDeliveredTrialNotices() async {
        let identifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(trialNoticeIdentifier) }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func decideTrialNotice() -> TrialNotice.Decision {
        TrialNotice.decision(
            screen: licenceScreen,
            now: date.now,
            sent: sentTrialNotices(),
            seenRunningUntil: defaults.value(.trialSeenRunningUntil)
        )
    }

    private func sentTrialNotices() -> TrialNotice.Sent {
        TrialNotice.Sent(
            dayBeforeForEnd: defaults.value(.trialDayBeforeNoticeSentForEnd),
            endedForEnd: defaults.value(.trialEndedNoticeSentForEnd)
        )
    }

    private func record(_ notice: TrialNotice, forEnd end: Date) {
        switch notice {
        case .dayBefore: defaults.setValue(.trialDayBeforeNoticeSentForEnd, value: end)
        case .ended: defaults.setValue(.trialEndedNoticeSentForEnd, value: end)
        }
    }

    private func showTrialNotice(_ notice: TrialNotice) async {
        let l10n = L10n.Trial.self
        let (title, body) = switch notice {
        case .dayBefore: (l10n.endsTomorrowNotificationTitle, l10n.endsTomorrowNotificationBody)
        case .ended: (l10n.endedNotificationTitle, l10n.endedNotificationBody)
        }
        do {
            logger.notice("Posting the trial notice: \(String(describing: notice), privacy: .public)")
            try await userNotificationsClient.showUserNotification(
                title: title,
                body: body,
                identifier: trialNoticeIdentifier,
                threadIdentifier: "Trial",
                delay: nil
            )
        } catch {
            logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Optimized battery charging

    func startObservingOptimizedBatteryCharging() {
        // Same as `startObservingChargingStateMode` — the identical pattern, the identical
        // leak. Not observed doubling in the wild only because this state changes rarely.
        optimizedBatteryChargingTask?.cancel()
        optimizedBatteryChargingTask = Task {
            for await (powerState, manageCharging) in combineLatest(
                powerSourceClient.powerSourceChanges(),
                defaults.observe(.manageCharging)
            ).debounce(for: .seconds(1), clock: AnyClock(self.clock)) {
                guard manageCharging, lastAlertDate.timeIntervalSinceNow < -60 * 60 * 8 else { continue }
                if let optimizedBatteryChargingEngaged = powerState.optimizedBatteryChargingEngaged, optimizedBatteryChargingEngaged {
                    lastAlertDate = date.now
                    showOptimizedBatteryChargingIsTurnedOn()
                }
            }
        }
    }

    func cancelObservingOptimizedBatteryCharging() {
        optimizedBatteryChargingTask?.cancel()
    }

    @MainActor
    func showOptimizedBatteryChargingIsTurnedOn() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.Notifications.Alert.Title.optimizedChargingTurnedOn
        alert.informativeText = L10n.Notifications.Alert.InformativeText.optimizedChargingTurnedOn
        alert.showsSuppressionButton = true
        alert.suppressionButton?.target = self
        alert.suppressionButton?.action = #selector(supressionWasSelected(_:))
        alert.addButton(withTitle: L10n.Common.ok)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }
    }

    @objc
    func supressionWasSelected(_ sender: NSButton) {
        defaults.setValue(.showOptimizedBatteryCharging, value: !(sender.state == .on))
    }

    // MARK: - Helpers

    func requestAuthorization() async -> Bool? {
        try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

extension NotificationsManager: @preconcurrency UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    public func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }
        if response.notification.request.identifier == updateNotificationIdentifier,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier
        {
            // If the notificaton is clicked on, make sure we bring the update in focus
            // If the app is terminated while the notification is clicked on,
            // this will launch the application and perform a new update check.
            // This can be more likely to occur if the notification alert style is Alert rather than Banner
            updater.checkForUpdates()
        } else if response.notification.request.identifier.hasPrefix(trialNoticeIdentifier),
                  response.actionIdentifier == UNNotificationDefaultActionIdentifier
        {
            openLicenceWindow()
        } else if response.actionIdentifier == settingsActionIdentifier {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }
    }
}

private extension LicenceScreen {
    /// The end date of the trial a notice is sent for.
    var trialEnd: Date? {
        switch self {
        case let .trialRunning(until, _): until
        case let .trialEnded(at): at
        case .licensed, .undetermined, .activateOnly, .offerTrial: nil
        }
    }
}
