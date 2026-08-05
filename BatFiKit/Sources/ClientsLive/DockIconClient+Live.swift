//
//  DockIconClient.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import AppKit
import AppShared
import Clients
import Dependencies

extension DockIconClient: DependencyKey {
    nonisolated(unsafe) public static var liveValue: DockIconClient = {
        .init(
            show: { show in
                DispatchQueue.main.async {
                    if show {
                        NSApp.setActivationPolicy(.regular)
                        activateApp()
                    } else {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        )
    }()
}
