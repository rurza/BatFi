//
//  PowerModeClient+Live.swift
//  BatFiKit
//
//  Created by Adam Różyński on 20.11.2024.
//

import AsyncAlgorithms
import Foundation
import Clients
import Dependencies

extension PowerModeClient: DependencyKey {
    public static var liveValue: Clients.PowerModeClient {
        let xpcClient = XPCClient.shared
        return Self(
            getCurrentPowerMode: {
                let (uint, highPowerModeIsAvailable) = try await xpcClient.getPowerMode()
                if let mode = PowerMode(uint: uint) {
                    return (mode, highPowerModeIsAvailable)
                } else {
                    throw PowerModeClientError.unsupportedMode
                }
            },
            setPowerMode: { powerMode, lowPowerModeOnly in
                do {
                    try await xpcClient.setPowerMode(powerMode.uint, lowPowerModeOnly: lowPowerModeOnly)
                    NotificationCenter.default.post(name: .powerModeDidChange, object: nil, userInfo: ["powerMode": powerMode.uint])
                } catch {
                    throw error
                }
            },
            observePowerMode: {
                merge(
                    AsyncStream<PowerMode> { continuation in
                        let task = Task {
                            while Task.isCancelled {
                                try await Task.sleep(for: .seconds(60), tolerance: .milliseconds(50))
                                let (uint, _) = try await xpcClient.getPowerMode()
                                if let mode = PowerMode(uint: uint) {
                                    continuation.yield(mode)
                                }
                            }
                        }
                        continuation.onTermination = { _ in
                            task.cancel()
                        }
                    },
                    NotificationCenter.default.notifications(named: .powerModeDidChange).compactMap { note in
                        guard let userInfo = note.userInfo, let uintValue = userInfo["powerMode"] as? UInt8, let mode = PowerMode(uint: uintValue) else {
                            return nil
                        }
                        return mode
                    }
                ).eraseToStream()
            }
        )
    }
}

extension Notification.Name {
    static let powerModeDidChange = Notification.Name("BatFiKit.PowerModeClient.PowerModeDidChange")
}

extension PowerMode {
    init?(uint: UInt8) {
        switch uint {
        case 0:
            self = .normal
        case 1:
            self = .low
        case 2:
            self = .high
        default:
            return nil
        }
    }

    var uint: UInt8 {
        switch self {
        case .low:
            1
        case .normal:
            0
        case .high:
            2
        }
    }
}
