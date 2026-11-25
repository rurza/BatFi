//
//  OtherChargeToolsClient+Live.swift
//  BatFi
//

import AppKit
import Clients
import Dependencies
import Foundation
import os
import Shared

private let OtherChargeToolsDidChangeNotificationName = Notification.Name("OtherChargeToolsDidChangeNotificationName")

private actor OtherChargeToolsState {
    private(set) var latest: [DetectedChargeTool]?

    func set(_ tools: [DetectedChargeTool]) {
        latest = tools
        NotificationCenter.default.post(name: OtherChargeToolsDidChangeNotificationName, object: tools)
    }
}

extension OtherChargeToolsClient: DependencyKey {
    public static let liveValue: OtherChargeToolsClient = {
        let logger = Logger(category: "Other Charge Tools")
        let state = OtherChargeToolsState()
        return OtherChargeToolsClient(
            detect: {
                // The real home: BatFi is not sandboxed, so this is /Users/<name> rather than
                // a container — which is where the battery CLI puts its LaunchAgent.
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let tools = OtherChargeToolDetection.detect(
                    homeDirectory: home,
                    fileExists: { FileManager.default.fileExists(atPath: $0) },
                    applicationURLs: { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
                )
                // Notice, not debug: customer logs drop debug lines, and this is the line a
                // report about a limit that will not hold needs most. Every footprint that
                // matched, with paths in the home folder written as ~, so it is public
                // without naming the user.
                let summary = tools.isEmpty ? "none" : tools.map { $0.logDescription(homeDirectory: home) }.joined(separator: "; ")
                logger.notice("Other charge-control tools installed: \(summary, privacy: .public)")
                await state.set(tools)
                return tools
            },
            latest: {
                await state.latest
            },
            observe: {
                AsyncStream<[DetectedChargeTool]?> { continuation in
                    let streamTask = Task {
                        // Subscribed before reading `latest`, so a scan that lands in between
                        // is delivered rather than lost.
                        let changes = NotificationCenter.default.notifications(named: OtherChargeToolsDidChangeNotificationName)
                        if let current = await state.latest {
                            continuation.yield(current)
                        }
                        for await note in changes {
                            continuation.yield(note.object as? [DetectedChargeTool])
                        }
                    }
                    continuation.onTermination = { _ in streamTask.cancel() }
                }
                .compactMap { $0 }
                .eraseToStream()
            }
        )
    }()
}
