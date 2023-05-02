//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import App
import SwiftUI

@main
struct BatFiApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        _EmptyScene()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var app = BatFi()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.start()
    }
}
