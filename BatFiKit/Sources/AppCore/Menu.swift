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
            
            for await (state, showDebugMenu) in combineLatest(
                appChargingState.observeChargingStateMode(), defaults.observe(.showDebugMenu)
            ) {
                updateMenu(appChargingState: state, showDebugMenu: showDebugMenu)
            }
        }
    }

    private func updateMenu(appChargingState: AppChargingMode, showDebugMenu: Bool) {
        let chargeTo100Tooltip: String?
        if appChargingState == .forceDischarge {
            chargeTo100Tooltip = L10n.Menu.Tooltip.ChargeToHundred.dischargeTurnedOn
        } else if appChargingState == .chargerNotConnected {
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
            if appChargingState == .forceDischarge || appChargingState == .chargerNotConnected {
                MenuItem(L10n.Menu.Label.chargeToHundred)
                    .toolTip(chargeTo100Tooltip)
            } else if appChargingState != .forceCharge {
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
                    if showDebugMenu {
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
