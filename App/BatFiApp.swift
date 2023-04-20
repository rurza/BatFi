//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import Combine
import MenuBuilder
import ServiceManagement
import SwiftUI
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service = SMAppService.daemon(plistName: helperPlistName)
        print("\(service) has status \(service.status)")
        try? service.register()

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
                self.client.sendMessage(
                    SMCChargingCommand.disableCharging,
                    to: XPCRoute.charging,
                    withResponse: self.xpcChargingResponse
                )
            }
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect(target: NSApp, action: #selector(NSApp.terminate(_:)))
                .shortcut("q")
        }
    }

    func xpcChargingResponse(_ result: Result<Bool, XPCError>) -> Void {
        print(result)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let service = SMAppService.daemon(plistName: helperPlistName)
        try? service.unregister()
    }
}
