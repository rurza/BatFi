//
//  Menu.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import AsyncAlgorithms
import AppShared
import AppKit
import BatteryInfo
import Clients
import L10n
import DefaultsKeys
import Dependencies
import MenuBuilder
import PowerCharts
import PowerInfo
import SwiftUI

@MainActor
public protocol MenuControllerDelegate: AnyObject {
    func forceCharge()
    func stopForceCharge()
    func openSettings()
    func quitApp()
    func openAbout()
    func checkForUpdates()
    func openOnboarding()
}

@MainActor
public final class MenuController {
    struct MenuDependencies {
        let appChargingState: AppChargingMode
        let showChart: Bool
        let showPowerDiagram: Bool
        let showHighImpactProcesses: Bool
        let showDebugMenu: Bool
    }


    let statusItem: NSStatusItem
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.helperManager) private var helperManager
    @Dependency(\.defaults) private var defaults

    public weak var delegate: MenuControllerDelegate?

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            
            for await ((state, showDebugMenu, showChart), (showPowerDiagram, showHighEnergyImpactProcesses)) in combineLatest(
                combineLatest(
                    appChargingState.observeChargingStateMode(),
                    defaults.observe(.showDebugMenu),
                    defaults.observe(.showChart)
                ),
                combineLatest(
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
                        showDebugMenu: showDebugMenu
                    )
                )
            }
        }
    }

    private func updateMenu(dependencies: MenuDependencies) {
        let chargeTo100Tooltip: String?
        if dependencies.appChargingState == .forceDischarge {
            chargeTo100Tooltip = L10n.Menu.Tooltip.ChargeToHundred.dischargeTurnedOn
        } else if dependencies.appChargingState == .chargerNotConnected {
            chargeTo100Tooltip = L10n.Menu.Tooltip.ChargeToHundred.chargerNotConnected
        } else {
            chargeTo100Tooltip = nil
        }
        self.statusItem.menu = NSMenu {
            MenuItem("")
                .view {
                    BatteryInfoView()
                }
            SeparatorItem()
            if dependencies.showChart {
                MenuItem("")
                    .view {
                        ChartsView()
                            .modifier(MenuViewModifier())
                            .frame(height: 120)

                    }
                SeparatorItem()
            }
            if dependencies.showPowerDiagram {
                MenuItem("")
                    .view {
                        PowerInfoView()
                            .modifier(MenuViewModifier())
                    }
                SeparatorItem()
            }
            if dependencies.appChargingState == .forceDischarge || dependencies.appChargingState == .chargerNotConnected {
                MenuItem(L10n.Menu.Label.chargeToHundred)
                    .toolTip(chargeTo100Tooltip)
            } else if dependencies.appChargingState != .forceCharge {
                MenuItem(L10n.Menu.Label.chargeToHundred)
                    .onSelect { [weak self] in
                        self?.delegate?.forceCharge()
                    }
            } else {
                MenuItem(L10n.Menu.Label.stopChargingToHundred).onSelect { [weak self] in
                    self?.delegate?.stopForceCharge()
                }
            }
            SeparatorItem()
            MenuItem(L10n.Menu.Label.more)
                .submenu {
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
}

private struct MenuViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
    }
}
