//
//  App.swift
//
//
//  Created by Adam on 02/05/2023.
//

import About
import AppCore
import AppShared
import Cocoa
import Dependencies
import KeyboardShortcuts
import L10n
import License
import MenuBuilder
import Notifications
import Onboarding
import Shared
import Settings
import StatusItemArrowKit

public final class BatFi: StatusItemManagerDelegate, HelperConnectionManagerDelegate, Sendable {
    private let licenseModel = LicenseModel()
    private lazy var settingsController = SettingsController(licenseModel: licenseModel)
    private lazy var persistenceManager = PersistenceManager()
    private lazy var magSafeColorManager = MagSafeColorManager()
    private lazy var analyticsManager = AnalyticsManager()
    private lazy var helperConnectionManager = HelperConnectionManager(delegate: self)

    private var chargingManager = ChargingManager()
    private var automationManager = AutomationManager()
    private var notificationsManager: NotificationsManager?
    private var statusItemManager: StatusItemManager?
    private var appDidLaunch: Bool = false

    public var chargingModeManager: ChargingModeManager { chargingManager }

    private weak var aboutWindow: NSWindow?
    private weak var onboardingWindow: OnboardingWindow?
    private weak var arrowWindow: ArrowWindow?
    @Dependency(\.analyticsClient) private var analyticsClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.dockIcon) private var dockIcon
    @Dependency(\.featureFlags) private var featureFlags
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.helperHealthClient) private var helperHealthClient
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.systemVersionClient) private var systemVersion
    @Dependency(\.updater) private var updater
    @Dependency(\.userNotificationsClient) private var userNotificationsClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.powerModeClient) private var powerModeClient

    public init() {}

    public func start(isBeta: Bool) {
        Task {
            await chargingManager.setLicenseModel(licenseModel)
            guard powerSourceClient.isRunningOnLaptop() else {
                showAppIsNotRunningOnLaptop()
                return
            }
            setFeatureFlags(beta: isBeta)
            analyticsManager.start(shouldEnable: isBeta || defaults.value(.sendAnalytics))
            updater.startUpdater()
            if defaults.value(.onboardingIsDone) {
                await runMigration()
                dockIcon.show(false)
                await setUpTheApp()
                helperConnectionManager.checkHelperHealth()
                observerKeyboardHotkeys()
                appDidLaunch = true
                if await !licenseModel.verifyCachedLicense() {
                    licenseModel.openLicenseWindow()
                }
            } else {
                openOnboarding()
            }
        }
    }

    public func willQuit() {
        let terminate = TerminateReply()
        Task {
            // A fallback now, rather than a competitor. At five seconds this was not backing
            // the sequence below up — it was racing it, and the work down there routinely
            // outlasted it: `restoreSystemDefaults()` alone makes several PowerUI round
            // trips and can spend ~2s reopening a dropped SMC connection. When this Task won,
            // the app terminated before `quitHelper()` had been sent at all.
            //
            // That is how a helper survived an in-place update. launchd binds the mach
            // service to the running *process*, so a helper that outlives the app keeps
            // answering after Sparkle has replaced the bundle underneath it, and the
            // relaunched app is routed to the previous build.
            //
            // Ten seconds, sized to clear the sequence below rather than to interrupt it.
            // Overshooting is cheap now: the helper watches this process and restores and
            // exits on its own when it dies, so the worst case here is an untidy quit rather
            // than a root daemon left running.
            try? await Task.sleep(for: .seconds(10))
            await analyticsClient.addBreadcrumb(category: .lifecycle, message: "Helper shutdown did not finish in time; terminating anyway")
            terminate.send()
        }
        Task {
            await self.chargingManager.appWillQuit()
            await self.magSafeColorManager.appWillQuit()
            try? await self.helperClient.quitHelper()
            terminate.send()
        }
    }

    public func shouldHandleReopen() {
        if !defaults.value(.showMenuBarIcon) && appDidLaunch {
            openSettings()
        }
    }

    public func handleOpeningURL(_ url: URL) {
        do {
            let key = try URLParser.parseURL(url)
            licenseModel.license = key
            licenseModel.verifyLicenseButtonClicked()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.License.cantUseLink
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.Common.ok)
            _ = alert.runModal()
        }
    }

    // MARK: - MenuControllerDelegate

    public func openSettings() {
        activateApp()
        settingsController.openSettings()
    }

    public func openAutomationSettings() {
        activateApp()
        settingsController.openAutomationSettings()
    }

    /// Reached from the status item's warning row, so it is always available even after the
    /// automatic guidance for a given state has been spent.
    ///
    /// Routed through the same mapping the automatic guidance uses, rather than keeping its
    /// own shorter one. This is the entry point the user chooses deliberately — they have
    /// seen a warning and gone looking for the explanation — so it is the worst place to
    /// answer with a different, and mostly wrong, story than the alert that prompted them.
    /// It previously answered every state except a foreign helper with "the helper is
    /// installed, macOS will not start it", which is false in three of them.
    public func showHelperTroubleshooting() {
        activateApp()
        Task { @MainActor in
            presentHelperGuidance(for: await helperHealthClient.currentHealth())
        }
    }

    public func removeHelperRequestedByUser() {
        helperConnectionManager.removeHelperRequestedByUser()
    }

    /// The single place that decides which helper alert a given health means.
    @MainActor
    private func presentHelperGuidance(for health: HelperHealth) {
        switch health {
        case let .degraded(.foreignHelper(conflict)):
            showHelperBelongsToAnotherCopy(conflict, otherCopyIsRunningAt: OtherRunningCopies.first()?.path)
        case .degraded(.staleRegistrationNeedsUserReset):
            showHelperNeedsManualReset()
        case .degraded(.requiresApproval):
            showHelperNeedsApproval()
        case let .degraded(.installFailed(reason)):
            showHelperIsNotInstalled(reason: reason)
        case .degraded(.registeredButUnreachable):
            showHelperIsNotResponding()
        case .degraded(.notRegistered):
            showHelperIsNotInstalled(reason: nil)
        // Healthy, or not yet determined. Nothing is known to be wrong, so the honest
        // answer is the reachability one rather than an invented fault.
        default:
            showHelperIsNotResponding()
        }
    }

    public func quitApp() {
        NSApp.terminate(nil)
    }

    public func checkForUpdates() {
        updater.checkForUpdates()
    }

    public func openAbout() {
        if aboutWindow == nil {
            let about = presentAboutWindow()
            aboutWindow = about
        } else {
            aboutWindow?.orderFrontRegardless()
        }
    }

    public func chargeToFull() {
        chargingManager.forceCharge()
    }

    public func dischargeBattery(to limit: Int) {
        chargingManager.dischargeBattery(to: limit)
    }

    public func stopOverride() {
        chargingManager.stopOverride()
    }

    public func openOnboarding() {
        Task { [weak self] in
            guard let self else { return }
            dockIcon.show(true)
            // Onboarding runs its own helper UI; a modal stacked on top of it helps nobody.
            helperConnectionManager.suppressesGuidance = true

            if onboardingWindow == nil {
                let window = OnboardingWindow(licenseModel: licenseModel) { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.setUpTheApp()
                        self.showStatusItemArrow()
                    }
                } onClose: { [weak self] in
                    Task {
                        self?.helperConnectionManager.suppressesGuidance = false
                        self?.dockIcon.show(false)
                    }
                }
                window.makeKeyAndOrderFront(nil)
                window.center()
                onboardingWindow = window
            } else {
                onboardingWindow?.makeKeyAndOrderFront(nil)
            }
            activateApp()
        }
    }

    // MARK: -

    private func setUpTheApp() async {
        await chargingManager.setUpObserving()
        await automationManager.setUpObserving()
        persistenceManager.setUpObserving()
        await magSafeColorManager.setUpObserving()

        if notificationsManager == nil {
            notificationsManager = NotificationsManager()
        }
        if statusItemManager == nil {
            statusItemManager = StatusItemManager(licenseModel: licenseModel)
            statusItemManager?.delegate = self
        }
    }

    private func runMigration() async {
        if systemVersion.currentSystemIsSequoiaOrNewer() && defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep) {
            defaults.setValue(.turnOnSystemChargeLimitingWhenGoingToSleep, value: false)
            try? await userNotificationsClient.showUserNotification(
                title: L10n.Notifications.Notification.Title.systemChargeLimitRemoved,
                body: L10n.Notifications.Notification.Body.systemChargeLimitRemoved,
                identifier: "software.micropixels.BatFi.migration.system_charge_limit",
                threadIdentifier: nil,
                delay: nil
            )
        }
    }

    private func setFeatureFlags(
        beta isBeta: Bool
    ) {
        if isBeta {
            featureFlags.enableFeatureFlag(.beta)
        }
    }

    @MainActor
    private func showStatusItemArrow() {
        if let statusItem = statusItemManager?.statusItem {
            let window = ArrowWindow(arrowSize: NSSize(width: 40, height: 120), statusItem: statusItem)
            arrowWindow = window
            window.show()
            Task { [weak self] in
                guard (try? await self?.clock.sleep(for: .seconds(7))) != nil else { return }
                self?.arrowWindow?.close()
            }
        }
    }

    private func observerKeyboardHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .dischargeBattery) { [weak self] in
            self?.dischargeBattery(to: 0)
        }
        KeyboardShortcuts.onKeyUp(for: .chargeToHundred) { [weak self] in
            self?.chargeToFull()
        }
        KeyboardShortcuts.onKeyUp(for: .stopOverride) { [weak self] in
            self?.stopOverride()
        }
        KeyboardShortcuts.onKeyUp(for: .inhibitCharging) { [weak self] in
            self?.chargingManager.inhibitCharging()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleLowPowerMode) { [weak self] in
            guard let self else { return }
            Task {
                guard let result = try? await self.powerModeClient.getCurrentPowerMode() else { return }
                let highPowerIsAvailable = result.1
                if result.0 != .low {
                    do {
                        try await self.powerModeClient.setPowerMode(.low, !highPowerIsAvailable)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.lowPowerModeOn,
                            body: "",
                            identifier: "low",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                } else {
                    do {
                        try await self.powerModeClient.setPowerMode(.normal, !highPowerIsAvailable)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.automaticPowerModeOn,
                            body: "",
                            identifier: "automatic",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                }
            }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleHighPowerMode) { [weak self] in
            guard let self else { return }
            Task {
                guard let result = try? await self.powerModeClient.getCurrentPowerMode(), result.1 else {
                    try? await self.userNotificationsClient.showUserNotification(
                        title: L10n.Notifications.Notification.Title.highPowerModeUnsupported,
                        body: "",
                        identifier: "high",
                        threadIdentifier: "powermode",
                        delay: nil
                    )
                    return
                }
                if result.0 != .high {
                    do {
                        try await self.powerModeClient.setPowerMode(.high, false)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.highPowerModeOn,
                            body: "",
                            identifier: "high",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                } else {
                    do {
                        try await self.powerModeClient.setPowerMode(.normal, false)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.automaticPowerModeOn,
                            body: "",
                            identifier: "automatic",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                }
            }
        }
    }

    public func statusItemIconDidAppear() {
        showStatusItemArrow()
        statusItemManager?.delegate = nil
    }

    /// The alert for "there is no helper", and the only helper alert whose primary button
    /// does something rather than pointing somewhere.
    ///
    /// Every other one names a switch the user has to find. Here there is no switch, because
    /// there is no registration — so the button asks macOS, and it is macOS that then
    /// prompts for approval or posts the background-item notification. That prompt is a
    /// consequence of a click, which is the whole point: registering a privileged daemon
    /// unasked, seconds after launch, reads as the app misbehaving.
    ///
    /// Reachable with onboarding long since completed, because the record is pruned later —
    /// when the copy of BatFi that registered it is deleted. So this deliberately does not
    /// send anyone back through onboarding to redo something they did months ago.
    func showHelperIsNotInstalled(reason: String?) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.helperInstallFailed
        // The reason is shown when there is one, because the ordinary refusal here is
        // "Operation not permitted" — the transient Background Task Management race — and
        // that is precisely what makes offering to try again honest rather than a guess.
        alert.informativeText = reason.map(L10n.Notifications.Alert.InformativeText.helperInstallFailed)
            ?? L10n.Notifications.Alert.InformativeText.helperNotInstalled
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.installHelper)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.close)
        if alert.runModal() == .alertFirstButtonReturn {
            helperConnectionManager.installHelperRequestedByUser()
        }
    }

    /// Distinct from `showHelperIsNotInstalled()` on purpose: in this state the helper *is*
    /// installed and approved, and telling the user to install it again sends them looking
    /// for a problem that isn't there.
    func showHelperIsNotResponding() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.helperNotResponding
        alert.informativeText = L10n.Notifications.Alert.InformativeText.helperNotResponding
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.close)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }

    /// The alert for the one helper failure with a reliable manual remedy.
    ///
    /// Deliberately instructional rather than diagnostic. macOS is holding a registration
    /// whose launch constraint can no longer be resolved, and the app has already spent its
    /// unregister/register attempt discovering that neither call clears it — `unregister()`
    /// disables the record without removing it, and the `register()` after it re-finds the
    /// same one and reports success. Turning the item off in Login Items is what destroys
    /// it, and that is a privileged operation the app has no way to perform.
    ///
    /// So the steps are numbered and name the exact switch. The user is not being asked to
    /// investigate anything; they are being asked to perform the single action that works.
    func showHelperNeedsManualReset() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.helperNeedsManualReset
        alert.informativeText = L10n.Notifications.Alert.InformativeText.helperNeedsManualReset
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.close)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }

    /// The alert for an installation that succeeded and is waiting on the user.
    ///
    /// macOS posts its own "Background Items Added" notification for this, which is easy to
    /// miss and says nothing about BatFi not working. Nothing here asks the user to install
    /// or repair anything, because nothing is broken: there is one switch, and it is off.
    func showHelperNeedsApproval() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.helperNeedsApproval
        alert.informativeText = L10n.Notifications.Alert.InformativeText.helperNeedsApproval
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.close)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }

    /// The alert for a helper that works perfectly, for somebody else.
    ///
    /// Kept apart from both other helper alerts because the instruction is the opposite of
    /// theirs. Nothing here is fixed in Login Items: the registration is present, enabled
    /// and correct, and toggling it re-enables the *same* record, still naming the other
    /// bundle. What the user has is two copies of BatFi, and what resolves it is having one.
    func showHelperBelongsToAnotherCopy(_ conflict: HelperOwnershipConflict, otherCopyIsRunningAt: String?) {
        let otherPath = otherCopyIsRunningAt ?? conflict.owningAppPath ?? conflict.runningExecutablePath
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.foreignHelper
        alert.informativeText = otherCopyIsRunningAt != nil
            ? L10n.Notifications.Alert.InformativeText.foreignHelperOtherCopyRunning(otherPath)
            : L10n.Notifications.Alert.InformativeText.foreignHelperOtherCopyInstalled(otherPath)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.showInFinder)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.close)
        if alert.runModal() == .alertFirstButtonReturn {
            // Selects the other copy rather than opening it: the user has to be able to see
            // *which* BatFi this is talking about before deciding what to do with it, and
            // the paths involved are usually two that look identical in a menu bar.
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: otherPath)])
        }
    }

    private func showAppIsNotRunningOnLaptop() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.notLaptop
        alert.informativeText = L10n.Notifications.Alert.InformativeText.notLaptop
        alert.addButton(withTitle: L10n.Menu.Label.quit)
        _ = alert.runModal()
        NSApp.terminate(nil)
    }
}

/// Answers `applicationShouldTerminate` exactly once, whichever path reaches it first.
///
/// `willQuit()` runs two Tasks — the shutdown sequence and the fallback that bounds it — and
/// both end in a reply. Which one arrives first is a race by design; replying twice is not.
///
/// Main-actor isolated to match `BatFi`, which picks up `@MainActor` from its
/// `StatusItemManagerDelegate` conformance, so the flag needs no synchronisation of its own.
@MainActor
private final class TerminateReply {
    private var hasReplied = false

    func send() {
        guard !hasReplied else { return }
        hasReplied = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}
