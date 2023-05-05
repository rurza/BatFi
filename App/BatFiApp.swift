//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import App
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var app = BatFi()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.start()
    }
}
