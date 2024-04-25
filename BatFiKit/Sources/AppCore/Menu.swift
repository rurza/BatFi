//
//  Menu.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import AppKit
import AppShared
import AsyncAlgorithms
import BatteryInfo
import Clients
import DefaultsKeys
import Dependencies
import HighEnergyUsage
import L10n
import MenuBuilder
import PowerCharts
import PowerDistributionInfo
import SharedUI
import SwiftUI

public protocol ChargingModeManager {
    func forceCharge()
    func stopForceCharge()
    func dischargeBattery()
    func stopDischargingBattery()
    func stopOverride()
    func inhibitCharging()
}

public protocol MenuControllerDelegate: AnyObject {
    @MainActor
    func openSettings()

    @MainActor
    func quitApp()

    @MainActor
    func openAbout()

    @MainActor
    func checkForUpdates()

    @MainActor
    func openOnboarding()

    var chargingModeManager: ChargingModeManager { get }
}

@MainActor
public final class MenuController {
    struct MenuDependencies {
        let appChargingState: AppChargingMode
        let showChart: Bool
        let showPowerDiagram: Bool
        let showHighImpactProcesses: Bool
        let showDebugMenu: Bool
        let lidOpened: Bool
    }

    let statusItem: NSStatusItem
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.helperClient) private var helperManager
    @Dependency(\.defaults) private var defaults

    public weak var delegate: MenuControllerDelegate?
    private let menuDelegate = MenuObserver.shared
    private let batteryInfoModel = BatteryInfoView.Model()

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
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

    private func updateMenu(dependencies: MenuDependencies) {
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
                        .frame(minWidth: 220)
                        .modifier(MenuViewModifier())
                        .environmentObject(batteryInfoModel)
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
            if let limit = tempChargingMode?.limit,
               ((limit != 0 && limit != 100) || !dependencies.appChargingState.chargerConnected) {
                SeparatorItem()
            }
            if let limit = tempChargingMode?.limit, limit != 0, limit != 100 {
                MenuItem(L10n.Menu.Label.stopOverride)
                    .onSelect { [weak self] in
                        self?.delegate?.chargingModeManager.stopOverride()
                    }
            }
            if let limit = tempChargingMode?.limit, !dependencies.appChargingState.chargerConnected {
                chargerNotConnectedTempOverrideDisclaimer(limit: limit)
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
}

private struct MenuViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 15)
            .padding(.top, 6)
            .padding(.bottom, 6)
    }
}
