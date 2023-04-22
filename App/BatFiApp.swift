//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import Combine
import MenuBuilder
import SwiftUI
import ServiceManagement
import SecureXPC

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
    var client: XPCClient!
    lazy var batteryLevelObserver = BatteryLevelObserver()
    lazy var serviceRegisterer = ServiceRegisterer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await serviceRegisterer.registerServices()
            } catch {
                if (error as NSError).domain == "SMAppServiceErrorDomain" {
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    print("service registration failed: \(error.localizedDescription)")
                }
            }
        }

        client = XPCClient.forMachService(
            named: helperBundleIdentifier,
            withServerRequirement: try! .sameBundle
        )

        statusItem.button?.image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "BatFi")
        statusItem.menu = NSMenu {
            MenuItem("").view {
                BatteryInfoView(batteryLevelObserver: batteryLevelObserver)
            }
            SeparatorItem()
            MenuItem("Turn off charging").onSelect { [weak self] in
                guard let self = self else { return }
                self.enableCharging(false)
            }
            MenuItem("Turn on charging").onSelect { [weak self] in
                guard let self = self else { return }
                self.enableCharging(true)
            }
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect(target: NSApp, action: #selector(NSApp.terminate(_:)))
                .shortcut("q")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? serviceRegisterer.unregisterService()
    }

    func enableCharging(_ enable: Bool) {
        Task {
            do {
                try await self.client.sendMessage(
                    enable ? SMCChargingCommand.enableCharging : SMCChargingCommand.disableCharging,
                    to: XPCRoute.charging
                )
                self.batteryLevelObserver.updateBatteryState()
            } catch {
                print(error)
            }
        }
    }
}
