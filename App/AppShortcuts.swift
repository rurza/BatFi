//
//  AppShortcuts.swift
//  BatFi
//
//  Created by Adam Różyński on 15/04/2024.
//

import AppIntents
import Foundation

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ChargeToFullIntent(),
            phrases: [
                "Charge the battery with \(.applicationName)",
                "Charge to 100% with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("app_shortcut.charge_to_full.short_title", defaultValue: "Charge the battery"),
            systemImageName: "bolt.fill"
        )
    }
}
 
