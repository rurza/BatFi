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

private let plistName = "software.micropixels.BatFi.helper.plist"

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
        let service = SMAppService.agent(plistName: plistName)
        print("\(service) has status \(service.status)")
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "BatFi")
        statusItem.menu = NSMenu {
            MenuItem("Install Helper tool").onSelect {

            }
        }
    }
}
