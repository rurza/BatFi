//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import App
import AppIntents
import LetsMove
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var app: BatFi?

    func applicationWillFinishLaunching(_ notification: Notification) {
        PFMoveToApplicationsFolderIfNecessary()
    }

    func applicationDidFinishLaunching(_: Notification) {
        app = BatFi()
        #if BETA
        app?.start(isBeta: true)
        #else
        app?.start(isBeta: false)
        #endif
        AppDependencyManager.shared.add(dependency: self.app!)
    }

    func applicationWillTerminate(_: Notification) {}

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        app?.willQuit()
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        app?.shouldHandleReopen()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        app?.handleOpeningURL(url)
    }

    @IBAction
    func openSettings(_ sender: Any?) {
        app?.openSettings()
    }

    @IBAction
    func openAbout(_ sender: Any?) {
        app?.openAbout()
    }
}
