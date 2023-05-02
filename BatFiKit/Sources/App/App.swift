//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Cocoa
import MenuBuilder

public final class BatFi {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    public init() { }

    public func start() {
        statusItem.button?.image = NSImage(systemSymbolName: "minus.plus.batteryblock.fill", accessibilityDescription: "BatFi icon")
        statusItem.menu = NSMenu {
            MenuItem("")
                .view {
                    BatteryInfoView()
                }
            SeparatorItem()
            MenuItem("Quit BatFi")
                .onSelect(target: NSApp, action: #selector(NSApp.terminate(_:)))
                .shortcut("q")
        }
    }
}
