//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

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
    lazy var xpcClient: XPCClient = {
        let client = XPCClient.forMachService(named: helperBundleIdentifier)
        return client
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service = SMAppService.daemon(plistName: helperPlistName)
        print("\(service) has status \(service.status)")
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "BatFi")
        statusItem.menu = NSMenu {
            MenuItem("Install Helper tool").onSelect {
                Task {
                    do {
                        print("will register, status: \(service.status.rawValue)")
                        try service.register()
                        print("did register")
                    } catch {
                        print("did not register, error: \(error.localizedDescription)")
                    }
                }
            }
            MenuItem("Remove the Helper tool").onSelect {
                Task {
                    do {
                        print("will unregister, status: \(service.status.rawValue)")
                        try await service.unregister()
                        print("DID unregister, status: \(service.status.rawValue)")
                    } catch {
                        print("did not register, error: \(error)")
                    }
                }
            }
            SeparatorItem()
            MenuItem("Turn off charging").onSelect {
                self.xpcClient.sendMessage(
                    SMCCommand.disableCharging,
                    to: XPCRoute.battery,
                    withResponse: self.xpcResponse
                )
            }
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect(target: NSApp, action: #selector(NSApp.terminate(_:)))
                .shortcut("q")
        }
    }

    func xpcResponse(_ result: Result<Bool, XPCError>) -> Void {
        print(result)
    }
}
