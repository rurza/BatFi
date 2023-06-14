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
        self.statusItem.menu = NSMenu {
            MenuItem("")
                .view {
                    BatteryInfoView()
                }
            SeparatorItem()
            if appChargingState == .forceDischarge || appChargingState == .chargerNotConnected {
                MenuItem("Charge to 100%")
            } else if appChargingState != .forceCharge {
                MenuItem("Charge to 100%")
                    .onSelect { [weak self] in
                        self?.delegate?.forceCharge()
                    }
            } else {
                MenuItem("Stop charging to 100%").onSelect { [weak self] in
                    self?.delegate?.stopForceCharge()
                }
            }
            SeparatorItem()
            MenuItem("More")
                .submenu {
                    MenuItem("BatFi…")
                        .onSelect { [weak self] in
                            self?.delegate?.openAbout()
                        }
                    MenuItem("Check for Updates…")
                        .onSelect { [weak self] in
                            self?.delegate?.checkForUpdates()
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
            MenuItem("Settings…")
                .onSelect { [weak self] in
                    self?.delegate?.openSettings()
                }
                .shortcut(",")
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect { [weak self] in
                    self?.delegate?.quitApp()
                }
                .shortcut("q")
        }

    }
}
