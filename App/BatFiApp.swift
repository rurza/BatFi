//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import Combine
import MenuBuilder
import os
import SecureXPC
import SwiftUI

@main
struct BatFiApp: App {
    @State private var chargingDisabled = false
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        _EmptyScene()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var client: XPCClient = makeClient()
    lazy var serviceRegisterer = HelperManager()
    private let batteryLevelObserver = BatteryLevelObserver.shared
    private var charging: Charging!
    private var timer: Timer?

    lazy var logger = Logger(category: "💻")

    func applicationWillFinishLaunching(_ notification: Notification) {
        
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? serviceRegisterer.registerServiceIfNeeded()
        charging = Charging(client: client)

        statusItem.button?.image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "BatFi")
        statusItem.menu = NSMenu {
            MenuItem("").view {
                BatteryInfoView(batteryLevelObserver: batteryLevelObserver)
            }
            SeparatorItem()
            MenuItem("Install Daemon").onSelect { [weak self] in
                guard let self = self else { return }
                try? self.serviceRegisterer.registerService()
            }
            MenuItem("Remove Daemon").onSelect { [weak self] in
                guard let self = self else { return }
                try? self.serviceRegisterer.removeService()
            }
            SeparatorItem()
            MenuItem("Turn off charging").onSelect { [weak self] in
                guard let self = self else { return }
            }
            MenuItem("Turn on charging").onSelect { [weak self] in
                Task {
                    guard let self = self else { return }
                    try await self.charging.autoChargingMode()
                }
            }
            MenuItem("Inhibit charging").onSelect { [weak self] in
                guard let self = self else { return }

            }
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect(target: NSApp, action: #selector(NSApp.terminate(_:)))
                .shortcut("q")
        }
    }

    func makeClient() -> XPCClient {
        return XPCClient.forMachService(
            named: helperBundleIdentifier,
            withServerRequirement: try! .sameTeamIdentifier
        )
    }
}
