//
//  Menu.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import AppShared
import BatteryInfo
import Clients
import Cocoa
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
    @Dependency(\.settingsDefaults) private var settingsDefaults

    public weak var delegate: MenuControllerDelegate?

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            for await state in appChargingState.observeChargingStateMode() {
                updateMenu(appChargingState: state)
            }
        }
    }

    private func updateMenu(appChargingState: AppChargingMode) {
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
                    MenuItem("Debug")
                        .submenu {
                            MenuItem("Install Helper").onSelect { [weak self] in
                                Task { try? await self?.helperManager.installHelper() }
                            }
                            MenuItem("Remove Helper").onSelect { [weak self] in
                                Task { try? await self?.helperManager.removeHelper() }
                            }
                        }
                    SeparatorItem()
                    MenuItem("BatFi…")
                        .onSelect { [weak self] in
                            self?.delegate?.openAbout()
                        }
                    MenuItem("Check for Updates…")
                        .onSelect { [weak self] in
                            self?.delegate?.checkForUpdates()
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
