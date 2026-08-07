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
import SharedUI
import SnapKit
import SwiftUI

public protocol ChargingModeManager {
    func forceCharge()
    func stopForceCharge()
    func dischargeBattery()
    func stopDischargingBattery()
    func stopOverride()
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
    private var showHighPowerMode = false
    private let menuDelegate = MenuObserver.shared
    private let batteryInfoModel = BatteryInfoViewModel()
    private var menuContentView: NSView?
    private var pendingMenuDependencies: MenuDependencies?
    private let licenseModel: LicenseModel

    @Dependency(\.defaults) private var defaults
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.helperClient) private var helperManager
    @Dependency(\.helperHealthClient) private var helperHealthClient
    @Dependency(\.powerModeClient) private var powerModeClient
    @Dependency(\.suspendingClock) private var clock


    public init(licenseModel: LicenseModel) {
        self.licenseModel = licenseModel
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
        menuStateTask = Task { [weak self] in
            guard let self else { return }
            for await ((state, showDebugMenu, showPowerModeOptions), (showChart, showPowerDiagram, showHighEnergyImpactProcesses), (powerMode, helperHealth)) in combineLatest(
                combineLatest(
                    appChargingState.appChargingModeDidChage(),
                    defaults.observe(.showDebugMenu),
                    defaults.observe(.showPowerModeOptions)
                ),
                combineLatest(
                    defaults.observe(.showChart),
                    defaults.observe(.showPowerDiagram),
                    defaults.observe(.showHighEnergyImpactProcesses)
                ),
                combineLatest(
                    self.$lastPowerMode.values.eraseToStream(),
                    self.$helperHealth.values.eraseToStream()
                )
            ) {
                updateMenu(
                    dependencies:
                        MenuDependencies(
                            appChargingState: state,
                            showChart: showChart,
                            showPowerDiagram: showPowerDiagram,
                            showHighImpactProcesses: showHighEnergyImpactProcesses,
                            showDebugMenu: showDebugMenu,
                            lidOpened: await appChargingState.lidOpened() ?? false,
                            showPowerModeOptions: showPowerModeOptions,
                            powerMode: powerMode,
                            helperHealth: helperHealth
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
        let contentWidth: CGFloat = 220
        let coordinator = MenuContentSizeCoordinator()

        let content = MenuContent(licenseModel: licenseModel)
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

        let totalWidth = contentWidth + 30
        hostingView.frame = NSRect(x: 0, y: 0, width: totalWidth, height: 1)

        return hostingView
    }

    @MainActor
    private func updateMenu(dependencies: MenuDependencies) {
        print("📊 updateMenu — memory: \(Self.memoryFootprint())")

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
                        MenuContent(licenseModel: licenseModel)
                            .environmentObject(batteryInfoModel)
                            .tint(.appAccent)
                            .frame(width: 220)
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
                helperNotRespondingDisclaimer
                SeparatorItem()
            }

            MenuItem(L10n.Menu.Label.chargeToHundred)
                .onSelect { [weak self] in
                    if tempChargingMode?.limit == 100 {
                        self?.delegate?.chargingModeManager.stopForceCharge()
                    } else {
                        self?.delegate?.chargingModeManager.forceCharge()
                    }
                }
                .state(tempChargingMode?.limit == 100 ? .on : .off)

            MenuItem(L10n.Menu.Label.dischargeBattery)
                .onSelect { [weak self] in
                    if tempChargingMode?.limit == 0 {
                        self?.delegate?.chargingModeManager.stopDischargingBattery()
                    } else {
                        self?.delegate?.chargingModeManager.dischargeBattery()
                    }
                }
                .state(tempChargingMode?.limit == 0 ? .on : .off)
            if let limit = tempChargingMode?.limit,
               limit == 0,
               dependencies.appChargingState.chargerConnected,
               !dependencies.lidOpened {
                lidClosedSoBatteryWontDischargeDisclaimer
            }

            if showInhibitChargingCommand(chargingMode: dependencies.appChargingState) {
                MenuItem(L10n.Menu.Label.inhibitCharging)
                    .onSelect { [weak self] in
                        self?.delegate?.chargingModeManager.inhibitCharging()
                    }
            }
            if let limit = tempChargingMode?.limit, !dependencies.appChargingState.chargerConnected {
                chargerNotConnectedTempOverrideDisclaimer(limit: limit)
            }
            if let limit = tempChargingMode?.limit,
               limit != 0,
               limit != 100 {
                SeparatorItem()
            }
            if let limit = tempChargingMode?.limit, limit != 0, limit != 100 {
                MenuItem(L10n.Menu.Label.stopOverride)
                    .onSelect { [weak self] in
                        self?.delegate?.chargingModeManager.stopOverride()
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
    func chargerNotConnectedTempOverrideDisclaimer(limit: Int) -> [NSMenuItem] {
        MenuItem("")
            .view {
                Text(L10n.Menu.Label.chargerNotConnectedDisclaimer)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: 220, alignment: .leading)
                    .padding(.leading, horizontalPadding(for: limit))
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
    }

    /// The consequence of the warning row above it, wrapped rather than spelled into the
    /// item's title: a plain `NSMenuItem` widens the whole menu to fit its title, and this
    /// sentence is far wider than the 220pt the menu's content is built for.
    @MenuBuilder
    var helperNotRespondingDisclaimer: [NSMenuItem] {
        MenuItem("")
            .view {
                Text(L10n.Menu.Label.helperNotRespondingDisclaimer)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: 220, alignment: .leading)
                    .padding(.leading, menuItemCheckMarkPadding)
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
                    .frame(width: 220, alignment: .leading)
                    .padding(.leading, menuItemCheckMarkPadding)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
    }

    func horizontalPadding(for limit: Int?) -> CGFloat {
        if (limit == 100 || limit == 0 || defaults.value(.showPowerModeOptions)) {
            return menuItemCheckMarkPadding
        } else {
            return 15
        }
    }

    private func showInhibitChargingCommand(chargingMode: AppChargingMode) -> Bool {
        guard chargingMode.chargerConnected else { return false }
        return chargingMode.mode == .charging || chargingMode.mode == .forceDischarge
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
                // The clients are captured instead of `self`. A `[weak self]` on the items alone
                // was not weak at all: the enclosing `submenu` closure escapes, so it had to hold
                // `self` strongly for the items to weaken it — and the menu is reachable from
                // `self`. These three items only ever need the two clients anyway.
                .submenu { [helperManager, defaults] in
                    MenuItem(L10n.Menu.Label.installHelper).onSelect {
                        Task { try? await helperManager.installHelper() }
                    }
                    MenuItem(L10n.Menu.Label.removeHelper).onSelect {
                        Task { try? await helperManager.removeHelper() }
                    }
                    SeparatorItem()
                    MenuItem(L10n.Menu.Label.resetSettings).onSelect {
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
    let showDebugMenu: Bool
    let lidOpened: Bool
    let showPowerModeOptions: Bool
    let powerMode: PowerMode?
    let helperHealth: HelperHealth
}

private struct MenuViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 15)
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
        print("🟢 MenuContentHostingView init")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        print("🔴 MenuContentHostingView deinit")
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

