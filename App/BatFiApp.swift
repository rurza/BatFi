//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import App
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var app = BatFi()

    func applicationDidFinishLaunching(_: Notification) {
        app.start()
    }

    func applicationWillTerminate(_: Notification) {}

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        app.willQuit()
        return .terminateLater
    }
}
