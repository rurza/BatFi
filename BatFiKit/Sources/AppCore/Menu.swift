//
//  Menu.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import AsyncAlgorithms
import AppShared
import BatteryInfo
import Clients
import Cocoa
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
            chargeTo100Tooltip = "Disabled because the \"Discharge battery when charged over limit\" is turned on"
        } else if appChargingState == .chargerNotConnected {
            chargeTo100Tooltip = "Disabled because the charger is not connected"
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
                    MenuItem("BatFi…")
                        .onSelect { [weak self] in
                            self?.delegate?.openAbout()
                        }
                    MenuItem("Check for Updates…")
                        .onSelect { [weak self] in
                            self?.delegate?.checkForUpdates()
                        }
                    MenuItem("Onboarding…")
                        .onSelect { [weak self] in
                            self?.delegate?.openOnboarding()
                        }
                    if showDebugMenu {
                        SeparatorItem()
                        MenuItem("Debug")
                            .submenu {
                                MenuItem("Install Helper").onSelect { [weak self] in
                                    Task { try? await self?.helperManager.installHelper() }
                                }
                                MenuItem("Remove Helper").onSelect { [weak self] in
                                    Task { try? await self?.helperManager.removeHelper() }
                                }
                                SeparatorItem()
                                MenuItem("Reset settings").onSelect { [weak self] in
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
