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
import IOKit.pwr_mgt

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
                let nsError = error as NSError
                if nsError.domain == "SMAppServiceErrorDomain" && nsError.code != kSMErrorAlreadyRegistered {
                    SMAppService.openSystemSettingsLoginItems()
                    print(nsError.code)
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

    private var sleepAssertion: IOPMAssertionID?

    func enableCharging(_ enable: Bool) {
        Task {
            do {
                try await self.client.sendMessage(
                    enable
                    ? SMCChargingCommand.auto
                    : SMCChargingCommand.inhibitCharging,
                    to: XPCRoute.charging
                )
                self.batteryLevelObserver.updateBatteryState()
            } catch {
                print(error)
            }
            if enable {
                if let sleepAssertion {
                    IOPMAssertionRelease(sleepAssertion)
                }
            } else {
                var assertionID: IOPMAssertionID = IOPMAssertionID(0)
                let reason: CFString = "BatFi" as NSString
                let cfAssertion: CFString = kIOPMAssertionTypePreventSystemSleep as NSString
                let success = IOPMAssertionCreateWithName(cfAssertion,
                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                reason,
                                &assertionID)
                if success == kIOReturnSuccess {
                    sleepAssertion = assertionID
                } else {
                    print("I will be sleeping, fucker")
                }
            }
        }
    }
}
