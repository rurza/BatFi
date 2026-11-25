//
//  StatusItemManager.swift
//
//
//  Created by Adam on 18/05/2023.
//

import AppKit
import AppShared
import AsyncAlgorithms
import BatteryInfo
import BatteryIndicator
import Clients
import Combine
import DefaultsKeys
import Dependencies
import HighEnergyUsage
import L10n
import License
import MenuBuilder
import PowerCharts
import PowerDistributionInfo
import Shared
import SharedUI
import SwiftUI

public protocol ChargingModeManager {
    func forceCharge()
    func stopForceCharge()
    func dischargeBattery()
    func stopDischargingBattery()
    func stopOverride()
    /// Ends a pause from the menu: a discharge pause puts back the discharge it replaced.
    func resumePause()
    func inhibitCharging()
}

@MainActor
public protocol StatusItemManagerDelegate: AnyObject {
    func openSettings()
    func quitApp()
    func openAbout()
    func checkForUpdates()
    func openOnboarding()
    func openAutomationSettings()
    func showHelperTroubleshooting()
    /// Routed through the app rather than calling `helperClient.removeHelper()` from here, so
    /// the helper health state machine learns the removal was asked for. Told only about the
    /// consequence, it reads an unreachable helper as the wedged case and re-registers — which
    /// put the daemon back about a second after it was removed.
    func removeHelperRequestedByUser()

    var chargingModeManager: ChargingModeManager { get }
}

@MainActor
public final class StatusItemManager {
    public weak var delegate: StatusItemManagerDelegate?
    public private(set) lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    weak var batteryIndicatorView: NSView?
    private lazy var batteryIndicatorModel = BatteryIndicatorViewModel()
    private lazy var statusItemModel = StatusItemModel()
    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?
    private var menuStateTask: Task<Void, Never>?
    private var menuOpenedTask: Task<Void, Never>?
    private var powerModeTask: Task<Void, Never>?
    @Published
    private var lastPowerMode: PowerMode?

    /// Mirrored into a published property so it can join the menu's `combineLatest` below,
    /// which is already at its maximum arity.
    @Published
    private var helperHealth: HelperHealth = .unknown
    /// Mirrored for the same reason as `helperHealth`: other charge-control tools found on
    /// this Mac, as the last scan saw them.
    @Published
    private var otherChargeTools: [DetectedChargeTool] = []
    private var showHighPowerMode = false
    private let menuDelegate = MenuObserver.shared
    private let batteryInfoModel = BatteryInfoViewModel()
    private var menuContentView: NSView?
    private var pendingMenuDependencies: MenuDependencies?
    private let licenseModel: LicenseModel
    private let unlockModel: UnlockModel

    @Dependency(\.defaults) private var defaults
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.helperClient) private var helperManager
    @Dependency(\.helperHealthClient) private var helperHealthClient
    @Dependency(\.otherChargeTools) private var otherChargeToolsClient
    @Dependency(\.powerModeClient) private var powerModeClient
    @Dependency(\.suspendingClock) private var clock


    public init(licenseModel: LicenseModel, unlockModel: UnlockModel) {
        self.licenseModel = licenseModel
        self.unlockModel = unlockModel
        setUp()
    }

    private func setUp() {
        setUpStatusItem()
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            for await showMenuBarIcon in defaults.observe(.showMenuBarIcon).removeDuplicates() {
                self.statusItem.isVisible = showMenuBarIcon
            }
        }
        Task {
            for await showStaticMenuBarIcon in defaults.observe(.showStaticMenuBarIcon).removeDuplicates() {
                setupStatusItemIcon(showStaticIcon: showStaticMenuBarIcon)
            }
        }
    }

    private func observeMenuState() {
        Task { [weak self] in
            guard let self else { return }
            if let result = try? await self.powerModeClient.getCurrentPowerMode() {
                self.lastPowerMode = result.0
                self.showHighPowerMode = result.1
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await health in helperHealthClient.observeHealth() {
                self.helperHealth = health
            }
        }
        Task { [weak self] in
            guard let self else { return }
            // Every scan — the one at launch and each one Charging settings runs when it
            // opens — so the row goes away once the user has removed the tool and looked.
            for await detected in otherChargeToolsClient.observe() where detected != self.otherChargeTools {
                self.otherChargeTools = detected
            }
        }
        menuStateTask = Task { [weak self] in
            guard let self else { return }
            for await ((state, pauseContext, (showDebugMenu, showPowerModeOptions)), ((showChart, showPowerDiagram, showHighEnergyImpactProcesses), isUnlocked), (powerMode, helperHealth, otherChargeTools)) in combineLatest(
                combineLatest(
                    appChargingState.appChargingModeDidChage(),
                    // Its own stream, so a change of it rebuilds the menu and reaches nothing
                    // that follows the charging state.
                    appChargingState.pauseContextDidChange(),
                    combineLatest(
                        defaults.observe(.showDebugMenu),
                        defaults.observe(.showPowerModeOptions)
                    )
                ),
                // What the SwiftUI block at the top shows, so a change re-lays it out: the
                // three settings, and the lock, which hides all of them — see `MenuSections`.
                combineLatest(
                    combineLatest(
                        defaults.observe(.showChart),
                        defaults.observe(.showPowerDiagram),
                        defaults.observe(.showHighEnergyImpactProcesses)
                    ),
                    unlockModel.statusChanges()
                        .map { $0 == .valid }
                        .removeDuplicates()
                ),
                combineLatest(
                    self.$lastPowerMode.values.eraseToStream(),
                    self.$helperHealth.values.eraseToStream(),
                    self.$otherChargeTools.values.eraseToStream()
                )
            ) {
                updateMenu(
                    dependencies:
                        MenuDependencies(
                            appChargingState: state,
                            showChart: showChart,
                            showPowerDiagram: showPowerDiagram,
                            showHighImpactProcesses: showHighEnergyImpactProcesses,
                            isUnlocked: isUnlocked,
                            showDebugMenu: showDebugMenu,
                            lidOpened: await appChargingState.lidOpened() ?? false,
                            showPowerModeOptions: showPowerModeOptions,
                            powerMode: powerMode,
                            helperHealth: helperHealth,
                            otherChargeTools: otherChargeTools,
                            chargeBackend: self.lastKnownChargeBackend,
                            pauseContext: pauseContext,
                            // The reading as the menu is built: the click judges its own.
                            batteryLevel: (try? await powerSourceClient.currentPowerSourceState())?.batteryLevel
                        )
                )
            }
        }
    }

    private func observePowerMode() {
        powerModeTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let result = try? await self.powerModeClient.getCurrentPowerMode() {
                    if result.0 != self.lastPowerMode {
                        self.lastPowerMode = result.0
                    }
                    if result.1 != self.showHighPowerMode {
                        self.showHighPowerMode = result.1
                    }
                }
                try? await self.clock.sleep(for: .seconds(1), tolerance: .milliseconds(50))
            }
        }
    }

    /// macOS 26 workaround: NSHostingView reports incorrect intrinsicContentSize inside NSMenu.
    /// Use SwiftUI's onGeometryChange to measure actual content height and feed it back to AppKit.
    @available(macOS 26, *)
    @MainActor
    private func makeMenuContentView() -> NSView {
        let contentWidth = MenuMetrics.contentWidth
        let coordinator = MenuContentSizeCoordinator()

        let content = MenuContent(licenseModel: licenseModel, trialModel: licenseModel.trialModel, unlockModel: unlockModel)
            .environmentObject(batteryInfoModel)
            .tint(.appAccent)
            .frame(width: contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(MenuViewModifier())
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                coordinator.reportHeight(height)
            }

        let hostingView = MenuContentHostingView(rootView: content)
        coordinator.onHeightChange = { [weak hostingView] height in
            hostingView?.updateFromSwiftUI(height: height)
        }

        hostingView.frame = NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 1)

        return hostingView
    }

    @MainActor
    private func updateMenu(dependencies: MenuDependencies) {
        #if DEBUG
            print("📊 updateMenu — memory: \(Self.memoryFootprint())")
        #endif

        // macOS 26 workaround: replaceItems detaches the cached MenuContentHostingView
        // from the menu's display window. While the menu is open the SwiftUI render
        // context doesn't recover after reattachment, leaving the top of the menu
        // visually empty. Defer the rebuild until the menu closes.
        if #available(macOS 26, *), menuDelegate.menuIsOpened, menuContentView != nil {
            pendingMenuDependencies = dependencies
            return
        }

        let tempChargingMode = dependencies.appChargingState.userTempOverride

        if statusItem.menu == nil {
            let menu = NSMenu()
            menu.delegate = menuDelegate
            statusItem.menu = menu
        }
        // On macOS 26, reuse cached view for performance (handles dynamic sizing).
        if #available(macOS 26, *) {
            if menuContentView == nil {
                menuContentView = makeMenuContentView()
            }
        }

        statusItem.menu?.replaceItems {
            // On macOS 26: use cached custom NSView for dynamic sizing
            // On macOS 15: use inline SwiftUI view so @Default property wrappers update
            if #available(macOS 26, *), let cachedView = menuContentView {
                MenuItem("").view(cachedView)
            } else {
                MenuItem("")
                    .view {
                        MenuContent(licenseModel: licenseModel, trialModel: licenseModel.trialModel, unlockModel: unlockModel)
                            .environmentObject(batteryInfoModel)
                            .tint(.appAccent)
                            .frame(width: MenuMetrics.contentWidth)
                            .frame(maxHeight: .infinity)
                            .modifier(MenuViewModifier())
                    }
            }
            // Stays for as long as the helper is broken, which is what lets the modal be
            // capped at one per launch without the failure becoming invisible.
            if case .degraded = dependencies.helperHealth {
                MenuItem(L10n.Menu.Label.helperNotResponding)
                    .onSelect { [weak self] in
                        self?.delegate?.showHelperTroubleshooting()
                    }
                helperNotRespondingDisclaimer(override: tempChargingMode)
                SeparatorItem()
            }
            // Stays for as long as another charge-control tool is installed. The details —
            // what it fights over on this Mac, and how to remove it — are in Charging
            // settings, which `openSettings()` opens on.
            if let title = OtherChargeToolWarning.menuTitle(for: dependencies.otherChargeTools),
               let detail = OtherChargeToolWarning.menuDetail(for: dependencies.otherChargeTools) {
                MenuItem(title)
                    .onSelect { [weak self] in
                        self?.delegate?.openSettings()
                    }
                menuDisclaimer(detail, leadingPadding: horizontalPadding(for: tempChargingMode))
                SeparatorItem()
            }

            MenuItem(L10n.Menu.Label.chargeToHundred)
                .onSelect { [weak self] in
                    if StatusMenuCommands.isChargeToFull(tempChargingMode) {
                        self?.delegate?.chargingModeManager.stopForceCharge()
                    } else {
                        self?.delegate?.chargingModeManager.forceCharge()
                    }
                }
                .state(StatusMenuCommands.isChargeToFull(tempChargingMode) ? .on : .off)

            MenuItem(L10n.Menu.Label.dischargeBattery)
                .onSelect { [weak self] in
                    if StatusMenuCommands.isRunOnBattery(tempChargingMode) {
                        self?.delegate?.chargingModeManager.stopDischargingBattery()
                    } else {
                        self?.delegate?.chargingModeManager.dischargeBattery()
                    }
                }
                .state(StatusMenuCommands.isRunOnBattery(tempChargingMode) ? .on : .off)
            if StatusMenuCommands.isRunOnBattery(tempChargingMode),
               dependencies.appChargingState.chargerConnected,
               !dependencies.lidOpened {
                lidClosedSoBatteryWontDischargeDisclaimer
            }

            // "Inhibit Charging" while charging, "Pause Discharging" while the battery
            // discharges on the charger — see `ManualInhibit.pauseOffered`.
            if let pauseTitle = StatusMenuCommands.pauseTitle(
                mode: dependencies.appChargingState,
                backend: dependencies.chargeBackend,
                context: dependencies.pauseContext,
                batteryLevel: dependencies.batteryLevel
            ) {
                MenuItem(pauseTitle)
                    .onSelect { [weak self] in
                        self?.delegate?.chargingModeManager.inhibitCharging()
                    }
            }
            if let tempChargingMode, !dependencies.appChargingState.chargerConnected {
                chargerNotConnectedTempOverrideDisclaimer(override: tempChargingMode)
            }
            if let tempChargingMode, StatusMenuCommands.showsStopOverride(for: tempChargingMode) {
                SeparatorItem()
            }
            if let tempChargingMode, StatusMenuCommands.showsStopOverride(for: tempChargingMode) {
                // "Resume Charging"/"Resume Discharging" for a pause, at any level, "Stop
                // Override" for the rest — see `StatusMenuCommands.stopOverrideTitle(for:)`.
                MenuItem(StatusMenuCommands.stopOverrideTitle(for: tempChargingMode))
                    .onSelect { [weak self] in
                        // Only the menu's Resume puts back the discharge a pause replaced;
                        // Stop Override, from the hotkey or Shortcuts, never does.
                        if tempChargingMode.isInhibit {
                            self?.delegate?.chargingModeManager.resumePause()
                        } else {
                            self?.delegate?.chargingModeManager.stopOverride()
                        }
                    }
            }

            if dependencies.showPowerModeOptions {
                let showHighPowerMode = self.showHighPowerMode
                SeparatorItem()
                MenuItem(L10n.Menu.Label.lowPowerMode)
                    .onSelect { [weak self] in
                        Task {
                            self?.lastPowerMode = .low
                            try? await self?.powerModeClient.setPowerMode(.low, !showHighPowerMode)
                        }
                    }
                    .state(dependencies.powerMode == .low ? .on : .off)
                MenuItem(L10n.Menu.Label.automaticPowerMode)
                    .onSelect { [weak self] in
                        Task {
                            self?.lastPowerMode = .normal
                            try? await self?.powerModeClient.setPowerMode(.normal, !showHighPowerMode)
                        }
                    }
                    .state(dependencies.powerMode == .normal ? .on : .off)
                if showHighPowerMode {
                    MenuItem(L10n.Menu.Label.highPowerMode)
                        .onSelect { [weak self] in
                            Task {
                                self?.lastPowerMode = .high
                                try? await self?.powerModeClient.setPowerMode(.high, !showHighPowerMode)
                            }
                        }
                        .state(dependencies.powerMode == .high ? .on : .off)
                }
            }

            SeparatorItem()
            MenuItem(L10n.Menu.Label.more)
                .submenu {
                    self.moreMenuItems(dependencies: dependencies)
                }
            MenuItem(L10n.Menu.Label.settings)
                .onSelect { [weak self] in
                    self?.delegate?.openSettings()
                }
                .shortcut(",")
            SeparatorItem()
            MenuItem(L10n.Menu.Label.quit)
                .onSelect { [weak self] in
                    self?.delegate?.quitApp()
                }
                .shortcut("q")
        }

        statusItem.menu?.items.forEach { $0.view?.needsLayout = true }
        statusItem.menu?.update()
    }

        private var menuItemCheckMarkPadding: CGFloat {
            if #available(macOS 26.0, *) {
                return 17
            } else {
                return 25
            }
        }

    @MenuBuilder
    func chargerNotConnectedTempOverrideDisclaimer(override: UserTempChargingMode) -> [NSMenuItem] {
        MenuItem("")
            .view {
                Text(L10n.Menu.Label.chargerNotConnectedDisclaimer)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: MenuMetrics.contentWidth, alignment: .leading)
                    .padding(.leading, horizontalPadding(for: override))
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
    }

    /// The consequence of the warning row above it, wrapped rather than spelled into the
    /// item's title: a plain `NSMenuItem` widens the whole menu to fit its title, and this
    /// sentence is far wider than the 220pt the menu's content is built for.
    @MenuBuilder
    func helperNotRespondingDisclaimer(override: UserTempChargingMode?) -> [NSMenuItem] {
        MenuItem("")
            .view {
                Text(L10n.Menu.Label.helperNotRespondingDisclaimer)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: MenuMetrics.contentWidth, alignment: .leading)
                    .padding(.leading, horizontalPadding(for: override))
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
    }

    @MenuBuilder
    func menuDisclaimer(_ text: String, leadingPadding: CGFloat? = nil) -> [NSMenuItem] {
        MenuItem("")
            .view {
                Text(text)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: MenuMetrics.contentWidth, alignment: .leading)
                    .padding(.leading, leadingPadding ?? menuItemCheckMarkPadding)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
    }

    @MenuBuilder
    var lidClosedSoBatteryWontDischargeDisclaimer: [NSMenuItem] {
        MenuItem("")
            .view {
                Text(L10n.Menu.Label.dischargingOverrideButLidIsClosed)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: MenuMetrics.contentWidth, alignment: .leading)
                    .padding(.leading, menuItemCheckMarkPadding)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
    }

    /// Where a note's text has to start to line up with the item titles above it. NSMenu
    /// reserves a checkmark column only while some item in the menu has a state, which here
    /// means "Charge to 100%" or "Run on Battery" is ticked or the power-mode options are
    /// shown; without that column the titles start further left. A pause at 0% or 100% ticks
    /// neither.
    func horizontalPadding(for override: UserTempChargingMode?) -> CGFloat {
        if StatusMenuCommands.isChargeToFull(override) || StatusMenuCommands.isRunOnBattery(override) || defaults.value(.showPowerModeOptions) {
            return menuItemCheckMarkPadding
        } else {
            return menuItemNoCheckMarkPadding
        }
    }

    private var menuItemNoCheckMarkPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 10
        } else {
            return 15
        }
    }

    /// This Mac's charge backend, or nil while it is unknown.
    ///
    /// Read synchronously off the `lastKnownChargeBackend` cache, the same way
    /// `ChargingView` and `RuleEditorView` read it: the backend is a property of the
    /// firmware, which cannot change while this process runs. The menu rebuilds on every
    /// mode change, so the first diagnostics call not having landed yet costs at most one
    /// stale build — and an unknown backend offers the command (`StatusMenuCommands`).
    private var lastKnownChargeBackend: ChargeBackend? {
        defaults.value(.lastKnownChargeBackend).flatMap(ChargeBackend.init(rawValue:))
    }

    @MenuBuilder
    func moreMenuItems(dependencies: MenuDependencies) -> [NSMenuItem] {
        MenuItem(L10n.Menu.Label.batfi)
            .onSelect { [weak self] in
                self?.delegate?.openAbout()
            }
        MenuItem(L10n.Menu.Label.checkForUpdates)
            .onSelect { [weak self] in
                self?.delegate?.checkForUpdates()
            }
        MenuItem(L10n.Menu.Label.onboarding)
            .onSelect { [weak self] in
                self?.delegate?.openOnboarding()
            }
        if dependencies.showDebugMenu {
            SeparatorItem()
            MenuItem(L10n.Menu.Label.debug)
                // The weak capture belongs here, on the closure that escapes, rather than on the
                // items: `[weak self]` on those alone was not weak at all, because the enclosing
                // `submenu` closure then had to hold `self` strongly for them to weaken it, and
                // the menu is reachable from `self`. The clients still come in directly — only
                // the removal needs `self`, to reach the delegate at the moment it is chosen
                // rather than at the moment the menu was built.
                .submenu { [weak self, helperManager, defaults] in
                    MenuItem(L10n.Menu.Label.installHelper)
                        .onSelect {
                            Task { try? await helperManager.installHelper() }
                        }
                    MenuItem(L10n.Menu.Label.removeHelper)
                        .onSelect {
                            self?.delegate?.removeHelperRequestedByUser()
                        }
                    SeparatorItem()
                    MenuItem(L10n.Menu.Label.resetSettings)
                        .onSelect {
                            defaults.resetSettings()
                        }
                }
        }
    }

    private func setUpStatusItem() {
        // Set autosave name and default position
        statusItem.autosaveName = "BatFiStatusItem"
        let positionKey = "NSStatusItem Preferred Position BatFiStatusItem"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(50, forKey: positionKey)
        }

        statusItem.isVisible = true
        setupStatusItemIcon(showStaticIcon: defaults.value(.showStaticMenuBarIcon))
        observeMenuState()
        menuOpenedTask = Task { [weak self] in
            guard let self else { return }
            for await menuIsOpened in menuDelegate.$menuIsOpened.values.removeDuplicates().eraseToStream() {
                if menuIsOpened {
                    observePowerMode()
                } else {
                    powerModeTask?.cancel()
                    powerModeTask = nil
                    if let pending = pendingMenuDependencies {
                        pendingMenuDependencies = nil
                        updateMenu(dependencies: pending)
                    }
                }
            }
        }
    }

    private func setupStatusItemIcon(showStaticIcon: Bool) {
        guard let button = statusItem.button else { fatalError() }
        button.subviews.forEach { $0.removeFromSuperview() }
        if showStaticIcon {
            let image = NSImage(resource: .statusBarIcon)
            button.image = image
            self.batteryIndicatorView = nil
            sizeCancellable?.cancel()
        } else {
            let hostingView = NSHostingView(
                rootView: StatusItem(
                    sizePassthrough: sizePassthrough,
                    batteryIndicatorModel: batteryIndicatorModel,
                    model: statusItemModel
                )
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 38, height: 13)
            button.frame = hostingView.frame
            button.image = NSImage()
            hostingView.wantsLayer = true
            button.addSubview(hostingView)
            self.batteryIndicatorView = hostingView
            sizeCancellable = sizePassthrough.sink { [weak self] size in
                let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
                self?.batteryIndicatorView?.frame = frame
                self?.statusItem.button?.frame = frame
            }
        }
    }
}

extension StatusItemManager {
    static func memoryFootprint() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let mb = Double(info.resident_size) / 1_048_576
            return String(format: "%.1f MB", mb)
        }
        return "N/A"
    }
}

struct MenuDependencies {
    let appChargingState: AppChargingMode
    let showChart: Bool
    let showPowerDiagram: Bool
    let showHighImpactProcesses: Bool
    /// A valid licence or a running trial. Locked, the top block drops the statistics and the
    /// automation card; carried here, like the three settings above, so the change rebuilds
    /// the menu at its new height.
    let isUnlocked: Bool
    let showDebugMenu: Bool
    let lidOpened: Bool
    let showPowerModeOptions: Bool
    let powerMode: PowerMode?
    let helperHealth: HelperHealth
    let otherChargeTools: [DetectedChargeTool]
    /// This Mac's charge backend, read from the `lastKnownChargeBackend` cache rather than
    /// fetched: a backend is a property of the firmware and cannot change while BatFi runs,
    /// and every pane that needs it already reads that cache. Nil while it is unresolved —
    /// see `StatusMenuCommands`.
    let chargeBackend: ChargeBackend?
    /// What a pause armed now is judged against, and the battery level it is judged at — see
    /// `ManualInhibit.holds`. Nil where not known yet, which offers the pause by mode alone.
    let pauseContext: PauseHoldContext?
    let batteryLevel: Int?
}

private enum MenuMetrics {
    /// Total width of the menu: what `MenuContent` is laid out at plus `MenuViewModifier`'s
    /// inset on each side. The SwiftUI block and the plain menu items below it then share one
    /// leading edge, and the block doesn't widen the menu past what AppKit draws its rows at.
    static let width: CGFloat = 250
    static let horizontalInset: CGFloat = 15
    /// What `MenuContent` itself is laid out at, once the insets are taken off.
    static let contentWidth: CGFloat = width - horizontalInset * 2
}

private struct MenuViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MenuMetrics.horizontalInset)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }
}

// MARK: - macOS 26 menu sizing workaround
//
// NSMenu on macOS 26 clips custom NSMenuItem views because NSHostingView.fittingSize
// and intrinsicContentSize return incorrect values in the NSMenu context.
// Solution: Use SwiftUI's onGeometryChange to measure the actual rendered content height,
// then feed it back to the hosting view's frame and intrinsicContentSize.

@available(macOS 26, *)
private class MenuContentSizeCoordinator {
    var onHeightChange: ((CGFloat) -> Void)?
    private var currentHeight: CGFloat = 0

    func reportHeight(_ height: CGFloat) {
        guard height > 0, abs(height - currentHeight) > 0.5 else { return }
        currentHeight = height
        onHeightChange?(height)
    }
}

@available(macOS 26, *)
private class MenuContentHostingView<Content: View>: NSHostingView<Content> {
    private var reportedHeight: CGFloat = 0

    required init(rootView: Content) {
        super.init(rootView: rootView)
        #if DEBUG
            print("🟢 MenuContentHostingView init")
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        #if DEBUG
            print("🔴 MenuContentHostingView deinit")
        #endif
    }

    override var intrinsicContentSize: NSSize {
        if reportedHeight > 0 {
            return NSSize(width: frame.width, height: reportedHeight)
        }
        return super.intrinsicContentSize
    }

    func updateFromSwiftUI(height: CGFloat) {
        reportedHeight = height
        let newSize = NSSize(width: frame.width, height: height)
        setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }
}

