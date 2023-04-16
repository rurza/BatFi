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

private let plistName = "software.micropixels.BatFi.Helper.plist"

let client = XPCClient.forMachService(named: "")

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service = SMAppService.daemon(plistName: plistName)
        print("\(service) has status \(service.status)")
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "BatFi")
        statusItem.menu = NSMenu {
            MenuItem("Install Helper tool").onSelect {
                do {
                    print("will register, status: \(service.status.rawValue)")
                    try service.register()
                    print("did register")
                } catch {
                    print("did not register, error: \(error)")
                }
            }
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect(target: NSApp, action: #selector(NSApp.terminate(_:)))
                .shortcut("q")
        }
    }
}
