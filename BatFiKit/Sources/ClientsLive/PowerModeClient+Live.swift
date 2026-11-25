//
//  PowerModeClient+Live.swift
//  BatFiKit
//
//  Created by Adam Różyński on 20.11.2024.
//

import AppShared
import Foundation
import Clients
import Dependencies
import os
import Shared

extension PowerModeClient: DependencyKey {
    public static var liveValue: Clients.PowerModeClient {
        let xpcClient = XPCClient.shared
        let logger = Logger(category: "Power Mode Client")
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
                AsyncStream<PowerMode> { continuation in
                    let (requests, requestContinuation) = AsyncStream<Void>.makeStream(
                        bufferingPolicy: .bufferingNewest(1)
                    )
                    let readingTask = Task {
                        await PowerModeRefresh.run(
                            requests: requests,
                            read: { try await xpcClient.getPowerMode().0 },
                            onValue: { uint in
                                if let mode = PowerMode(uint: uint) {
                                    continuation.yield(mode)
                                }
                            },
                            onError: { error in
                                logger.error("Reading the power mode failed: \(error, privacy: .public)")
                            }
                        )
                    }
                    // macOS posts this whenever Low Power Mode turns on or off, from System
                    // Settings, Control Center or anyone else, so the icon follows within a
                    // read instead of waiting for the next poll. It only says *that*
                    // something changed: the mode itself still comes from the helper, which
                    // tells low, normal and high apart where ProcessInfo cannot. A burst of
                    // posts folds into at most one read after the one in flight.
                    nonisolated(unsafe) let powerStateObserver = NotificationCenter.default.addObserver(
                        forName: .NSProcessInfoPowerStateDidChange,
                        object: nil,
                        queue: nil
                    ) { _ in
                        requestContinuation.yield()
                    }
                    // The fallback for changes that notification may not cover: it is about
                    // Low Power Mode, so a switch between normal and High Power Mode is not
                    // known to post it. Sleeping throws only on cancellation, which is what
                    // ends the poll.
                    let pollingTask = Task {
                        while !Task.isCancelled {
                            requestContinuation.yield()
                            try await Task.sleep(for: .seconds(60), tolerance: .milliseconds(50))
                        }
                    }

                    let notificationTask = Task {
                        for await note in NotificationCenter.default.notifications(named: .powerModeDidChange) {
                            guard let userInfo = note.userInfo,
                                  let uintValue = userInfo["powerMode"] as? UInt8,
                                  let mode = PowerMode(uint: uintValue)
                            else { continue }
                            continuation.yield(mode)
                        }
                    }

                    continuation.onTermination = { _ in
                        NotificationCenter.default.removeObserver(powerStateObserver)
                        pollingTask.cancel()
                        requestContinuation.finish()
                        readingTask.cancel()
                        notificationTask.cancel()
                    }
                }
            },
            powerModeBySource: {
                await xpcClient.powerModeBySource()
            },
            setBatteryPowerMode: { value, usesPowermodeKey in
                try await xpcClient.setBatteryPowerMode(value, usesPowermodeKey: usesPowermodeKey)
                // The battery icon listens for this, and shows the mode *in use* — which is
                // the AC profile's whenever the Mac is on the charger, as it is when BatFi
                // gives the setting back. So the value written is not simply assumed: the
                // mode in use is asked for, and the value written stands in only where that
                // cannot be read (Macs that publish `lowpowermode`, which `getPowerMode`
                // does not read). Off the caller's path, since it is only the icon.
                Task {
                    let inUse = (try? await xpcClient.getPowerMode())?.0 ?? value
                    NotificationCenter.default.post(name: .powerModeDidChange, object: nil, userInfo: ["powerMode": inUse])
                }
            },
            armPowerModeRestoreOnExit: { record in
                try await xpcClient.armPowerModeRestoreOnExit(record)
            },
            lowPowerModeActiveChanges: {
                AsyncStream<Bool> { continuation in
                    // Observed before the first reading rather than after, so a change that
                    // lands between the two still arrives.
                    nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                        forName: .NSProcessInfoPowerStateDidChange,
                        object: nil,
                        queue: nil
                    ) { _ in
                        continuation.yield(ProcessInfo.processInfo.isLowPowerModeEnabled)
                    }
                    continuation.yield(ProcessInfo.processInfo.isLowPowerModeEnabled)
                    continuation.onTermination = { _ in
                        NotificationCenter.default.removeObserver(observer)
                    }
                }
            }
        )
    }
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
