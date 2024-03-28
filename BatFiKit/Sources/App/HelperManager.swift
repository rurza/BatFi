//
//  HelperManager.swift
//
//
//  Created by Adam Różyński on 27/03/2024.
//

import Dependencies
import Foundation
import Notifications
import os
import Shared
import ServiceManagement

public final class HelperManager {
    @Dependency(\.helperClient) var helperClient
    @Dependency(\.userNotificationsClient) var notificationsClient
    private lazy var logger = Logger(category: "Helper Manager")
    private var lastStatus: SMAppService.Status?

    // 1. Ping helper every 10s in a loop
    // 2. if it fails then take helper status
    // 3. Observe helper status
    // 4. if helper is not registered or not found then install helper
    // 5. if helper requires approval then show user notification
    // 6. if helper is installed it means it's a macOS bug and reinstall helper by removing and installing it again
    func observeHelperStatus() {
        Task {
            while !Task.isCancelled {
                do {
                    try await helperClient.pingHelper()
                    try? await Task.sleep(for: .seconds(10))
                } catch {
                    await quitAndPingHelper()
                }
            }
        }
    }

    private func quitAndPingHelper() async {
        logger.notice("Quitting and pinging helper")
        do {
            try await helperClient.quitHelper()
            try? await Task.sleep(for: .seconds(1))
            try await helperClient.pingHelper()
        } catch {
            logger.error("Failed to quit/ping helper: \(error)")
            for await status in helperClient.observeHelperStatus() {
                switch status {
                case .notRegistered, .notFound:
                    await installHelper()
                    break
                case .enabled:
                    do {
                        try await helperClient.pingHelper()
                    } catch {
                        await reinstallHelper()
                        try? await Task.sleep(for: .seconds(10))
                    }
                    break
                case .requiresApproval:
                    logger.warning("Helper installation requires approval")
                    _ = await notificationsClient.requestAuthorization()
                    try? await notificationsClient.showUserNotification(
                        title: "Helper installation requires approval",
                        body: "",
                        identifier: "software.microservices.BatFiKit.HelperInstallationRequiresApproval",
                        threadIdentifier: nil,
                        delay: nil
                    )
                @unknown default:
                    break
                }
            }
        }
    }

    private func installHelper() async {
        do {
            try await helperClient.installHelper()
        } catch {
            logger.error("Failed to install helper: \(error)")
            try? await notificationsClient.showUserNotification(
                title: "Helper installation failed",
                body: "Open System Settings -> General -> Login Items and enable BatFi Helper manually",
                identifier: "software.microservices.BatFiKit.HelperInstallationFailed",
                threadIdentifier: nil,
                delay: nil
            )
        }
    }

    private func pingHelper() async {
        do {
            try await helperClient.pingHelper()
        } catch {
            await reinstallHelper()
        }
    }

    private func reinstallHelper() async {
        logger.warning("Reinstalling helper")
        try? await helperClient.removeHelper()
        try? await Task.sleep(for: .seconds(1))
        try? await helperClient.installHelper()
    }
}
