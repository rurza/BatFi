//
//  DockIconClient.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import AppKit
import Clients
import Dependencies

extension DockIconClient: DependencyKey {
    public static var liveValue: DockIconClient = {
        .init(
            show: { show in
                if show {
                    await NSApp.setActivationPolicy(.regular)
                    NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                } else {
                    await NSApp.setActivationPolicy(.accessory)
                }
            }
        )
    }()
}
