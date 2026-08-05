//
//  HelperHealthClient+Live.swift
//  BatFi
//
//  Created by Adam Różyński on 05/08/2026.
//

import AppShared
import Clients
import Dependencies
import Foundation
import os

/// Posted by `XPCClient` when a connection invalidates or is interrupted.
let HelperConnectionDidFailNotificationName = Notification.Name("HelperConnectionDidFailNotificationName")
private let HelperHealthDidChangeNotificationName = Notification.Name("HelperHealthDidChangeNotificationName")

private actor HelperHealthState {
    var health: HelperHealth = .unknown

    func setHealth(_ newHealth: HelperHealth) {
        guard newHealth != health else { return }
        health = newHealth
        NotificationCenter.default.post(name: HelperHealthDidChangeNotificationName, object: newHealth)
    }
}

extension HelperHealthClient: DependencyKey {
    public static let liveValue: HelperHealthClient = {
        let logger = Logger(category: "Helper Health")
        let state = HelperHealthState()
        return HelperHealthClient(
            currentHealth: {
                await state.health
            },
            observeHealth: {
                AsyncStream<HelperHealth?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.health)
                        for await note in NotificationCenter.default.notifications(named: HelperHealthDidChangeNotificationName) {
                            continuation.yield(note.object as? HelperHealth)
                        }
                    }
                    continuation.onTermination = { _ in streamTask.cancel() }
                }
                .compactMap { $0 }
                .eraseToStream()
            },
            setHealth: { newHealth in
                logger.notice("Helper health: \(String(describing: newHealth), privacy: .public)")
                await state.setHealth(newHealth)
            },
            reportConnectionFailure: {
                NotificationCenter.default.post(name: HelperConnectionDidFailNotificationName, object: nil)
            },
            observeConnectionFailures: {
                AsyncStream<Void> { continuation in
                    let streamTask = Task {
                        for await _ in NotificationCenter.default.notifications(named: HelperConnectionDidFailNotificationName) {
                            continuation.yield(())
                        }
                    }
                    continuation.onTermination = { _ in streamTask.cancel() }
                }
            }
        )
    }()
}
