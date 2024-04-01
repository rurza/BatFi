//
//  InstallerApp.swift
//  Installer
//
//  Created by Adam Różyński on 30/03/2024.
//

import SwiftUI

@main
struct InstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appInstaller = AppInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView(appInstaller: appInstaller)
                .frame(width: 340)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}
