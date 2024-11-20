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

    var chargingModeManager: ChargingModeManager { get }
}

@MainActor
public final class StatusItemManager {
    public weak var delegate: StatusItemManagerDelegate?
    public private(set) var statusItem: NSStatusItem?

    weak var batteryIndicatorView: NSView?
    private lazy var batteryIndicatorModel = BatteryIndicatorViewModel()
    private lazy var statusItemModel = StatusItemModel()
    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?
    private var menuStateTask: Task<Void, Never>?
    private let menuDelegate = MenuObserver.shared
    private let batteryInfoModel = BatteryInfoViewModel()

    @Dependency(\.defaults) private var defaults
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.helperClient) private var helperManager

    public init() {
        setUp()
    }

    private func setUp() {

        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            for await showMenuBarIcon in defaults.observe(.showMenuBarIcon).removeDuplicates() {
                if !showMenuBarIcon {
                    self.statusItem = nil
                    self.batteryIndicatorView = nil
                    menuStateTask?.cancel()
                    menuStateTask = nil
                    sizeCancellable?.cancel()
                    sizeCancellable = nil
                } else {
                    if self.statusItem == nil {
                        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                        setUpStatusItem()
                    }
                }
            }
        }
    }

    private func setUpObservingMenuState() {
        menuStateTask = Task {
            for await ((state, showDebugMenu), (showChart, showPowerDiagram, showHighEnergyImpactProcesses)) in combineLatest(
                combineLatest(
                    appChargingState.appChargingModeDidChage(),
                    defaults.observe(.showDebugMenu)
                ),
                combineLatest(
                    defaults.observe(.showChart),
                    defaults.observe(.showPowerDiagram),
                    defaults.observe(.showHighEnergyImpactProcesses)
                )
            ) {
                updateMenu(dependencies:
                            MenuDependencies(
                                appChargingState: state,
                                showChart: showChart,
                                showPowerDiagram: showPowerDiagram,
                                showHighImpactProcesses: showHighEnergyImpactProcesses,
                                showDebugMenu: showDebugMenu,
                                lidOpened: await appChargingState.lidOpened() ?? false
                            )
                )
            }
        }
    }

    @MainActor
    private func updateMenu(dependencies: MenuDependencies) {
        guard let statusItem else { return }
        let tempChargingMode = dependencies.appChargingState.userTempOverride

        if statusItem.menu == nil {
            let menu = NSMenu()
            menu.delegate = menuDelegate
            statusItem.menu = menu
        }
        statusItem.menu?.replaceItems {
            MenuItem("")
                .view {
                    MenuContent()
                        .environmentObject(batteryInfoModel)
                        .frame(width: 220)
                        .frame(maxHeight: .infinity)
                        .modifier(MenuViewModifier())
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

    private let menuItemCheckMarkPadding: CGFloat = 25

    @MenuBuilder
    func chargerNotConnectedTempOverrideDisclaimer(limit: Int) -> [NSMenuItem] {
        MenuItem("")
            .view {
                Text(L10n.Menu.Label.chargerNotConnectedDisclaimer)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.tertiary)
                    .frame(width: 220, alignment: .leading)
                    .padding(.horizontal, horizontalPadding(for: limit))
                    .padding(.top, 6)
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
                    .padding(.horizontal, menuItemCheckMarkPadding)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
    }

    func horizontalPadding(for limit: Int?) -> CGFloat {
        if (limit == 100 || limit == 0) {
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
                .submenu {
                    MenuItem(L10n.Menu.Label.installHelper).onSelect { [weak self] in
                        Task { try? await self?.helperManager.installHelper() }
                    }
                    MenuItem(L10n.Menu.Label.removeHelper).onSelect { [weak self] in
                        Task { try? await self?.helperManager.removeHelper() }
                    }
                    SeparatorItem()
                    MenuItem(L10n.Menu.Label.resetSettings).onSelect { [weak self] in
                        self?.defaults.resetSettings()
                    }
                }
        }
    }

    private func setUpStatusItem() {
        guard let button = statusItem?.button else { fatalError() }
        let hostingView = NSHostingView(
            rootView: StatusItem(
                sizePassthrough: sizePassthrough,
                batteryIndicatorModel: batteryIndicatorModel,
                model: statusItemModel
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 38, height: 13)
        button.frame = hostingView.frame
        hostingView.wantsLayer = true
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(hostingView)
        self.batteryIndicatorView = hostingView
        sizeCancellable = sizePassthrough.sink { [weak self] size in
            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
            self?.batteryIndicatorView?.frame = frame
            self?.statusItem?.button?.frame = frame
        }
        setUpObservingMenuState()
    }
}

struct MenuDependencies {
    let appChargingState: AppChargingMode
    let showChart: Bool
    let showPowerDiagram: Bool
    let showHighImpactProcesses: Bool
    let showDebugMenu: Bool
    let lidOpened: Bool
}

private struct MenuViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 15)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }
}
