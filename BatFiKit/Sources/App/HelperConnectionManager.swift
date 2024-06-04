//
//  HelperConnectionManager.swift
//
//
//  Created by Adam Różyński on 06/05/2024.
//

import AsyncAlgorithms
import Clients
import Dependencies
import Foundation
import L10n

protocol HelperConnectionManagerDelegate: AnyObject {
    @MainActor
    func showHelperIsNotInstalled()
}

final class HelperConnectionManager {
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.userNotificationsClient) private var userNotificationsClient

    weak var delegate: HelperConnectionManagerDelegate?

    init(delegate: HelperConnectionManagerDelegate) {
        self.delegate = delegate
        observerHelperConnection()
    }

    func checkHelperHealth() {
        Task {
            let status = await helperClient.helperStatus()
            if status == .notRegistered {
                do {
                    try await helperClient.installHelper()
                } catch {
                    await delegate?.showHelperIsNotInstalled()
                }
            } else if status == .requiresApproval || status == .notFound {
                await delegate?.showHelperIsNotInstalled()
            } else if status == .enabled {
                do {
                    _ = try await helperClient.pingHelper()
                } catch {
                    await delegate?.showHelperIsNotInstalled()
                }
            }
        }
    }

    func observerHelperConnection() {
        Task {
            for await _ in appChargingState
                .appChargingModeDidChage()
                .debounce(for: .seconds(30))
                .filter({ $0.mode == .initial }) {
                let status = await helperClient.helperStatus()
                guard status == .enabled else { continue }
                try await userNotificationsClient.showUserNotification(
                    title: "⚠️ Houston, we have a problem.",
                    body: "The app is stuck in the initial mode. Restart your Mac.",
                    identifier: "software.micropixels.BatFi.notifications.initial_mode",
                    threadIdentifier: nil,
                    delay: nil
                )
            }
        }
    }
}
