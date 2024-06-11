//
//  PowerSourceClient.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import os
import Shared

extension PowerSourceClient: DependencyKey {
    public static let liveValue: PowerSourceClient = {
        let logger = Logger(category: "Power Source")
        let observer = Observer(logger: logger)
        let batteryHealthState = BatteryHealthState()

        @Sendable
        func getBatteryHealthIfNeeded() async -> Int? {
            if let batteryHealth = await batteryHealthState.lastBatteryHealth,
                batteryHealth.date.timeIntervalSinceNow > -60 * 60 {
                return batteryHealth.health
            }
            let task = Process()
            task.launchPath = "/usr/sbin/system_profiler"
            task.arguments = ["SPPowerDataType"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.launch()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                let lines = output.split(separator: "\n")
                for line in lines {
                    if line.contains("Maximum Capacity") {
                        let components = line.components(separatedBy: ":")
                        if components.count == 2 {
                            let maximumCapacity = components[1].trimmingCharacters(in: .whitespaces.union(.decimalDigits.inverted))
                            guard let capacityInteger = Int(maximumCapacity) else { return nil }
                            await batteryHealthState.setBatteryHealth(.init(health: capacityInteger, date: .now))
                            return capacityInteger
                        }
                        return nil
                    }
                }
            }

            return nil
        }

        @Sendable
        func getPowerSourceInfo() async throws -> PowerState {
            func getValue<DataType>(_ identifier: String, from service: io_service_t) -> DataType? {
                if let valueRef = IORegistryEntryCreateCFProperty(service, identifier as CFString, kCFAllocatorDefault, 0) {
                    let value = valueRef.takeUnretainedValue() as? DataType
                    valueRef.release()
                    return value
                }

                return nil
            }

            let snapshotRef = IOPSCopyPowerSourcesInfo()
            defer { snapshotRef?.release() }
            let snapshot = snapshotRef?.takeUnretainedValue()
            let sourcesRef = IOPSCopyPowerSourcesList(snapshot)
            defer { sourcesRef?.release() }
            let sources = sourcesRef!.takeUnretainedValue() as Array
            let info = IOPSGetPowerSourceDescription(snapshot, sources[0]).takeUnretainedValue() as! [String: AnyObject]

            let batteryLevel = info[kIOPSCurrentCapacityKey] as? Int
            let isCharging = info[kIOPSIsChargingKey] as? Bool
            let powerSource = info[kIOPSPowerSourceStateKey] as? String
            let timeLeft = info[kIOPSTimeToEmptyKey] as? Int
            let timeToCharge = info[kIOPSTimeToFullChargeKey] as? Int
            let optimizedBatteryCharging = info["Optimized Battery Charging Engaged"] as? Bool

            guard
                let batteryLevel,
                let isCharging,
                let powerSource,
                let timeLeft,
                let timeToCharge,
                let optimizedBatteryCharging
            else {
                throw PowerSourceError.infoMissing
            }

            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            defer {
                IOServiceClose(service)
                IOObjectRelease(service)
            }

            guard let cycleCount: Int = getValue(kIOPMPSCycleCountKey, from: service) else {
                throw PowerSourceError.infoMissing
            }

            guard let temperature: Double = getValue("VirtualTemperature", from: service) else {
                throw PowerSourceError.infoMissing
            }
            let batteryTemperature = temperature / 100

            guard let chargerConnected: Bool = getValue(kIOPMPSExternalConnectedKey, from: service) else {
                throw PowerSourceError.infoMissing
            }

            let powerState = PowerState(
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                powerSource: powerSource,
                timeLeft: timeLeft,
                timeToCharge: timeToCharge,
                batteryCycleCount: cycleCount,
                batteryHealth: await getBatteryHealthIfNeeded(),
                batteryTemperature: batteryTemperature,
                chargerConnected: chargerConnected,
                optimizedBatteryChargingEngaged: optimizedBatteryCharging
            )
            return powerState
        }

        let client = PowerSourceClient(
            powerSourceChanges: {
                AsyncStream { continuation in
                    Task {
                        do {
                            let initialState = try await getPowerSourceInfo()
                            continuation.yield(initialState)
                        } catch {
                            logger.error("Can't get the current power source info")
                        }
                    }

                    let id = observer.addHandler {
                        Task {
                            do {
                                let powerState = try await getPowerSourceInfo()
                                logger.notice("Power state did change: \(powerState, privacy: .public)")
                                continuation.yield(powerState)
                            } catch {
                                logger.error("New power state, but there is an info missing")
                            }
                        }
                    }
                    continuation.onTermination = { _ in
                        observer.removeHandler(id)
                    }
                }
            },
            currentPowerSourceState: {
                try await getPowerSourceInfo()
            }
        )

        return client
    }()

    private class Observer {
        private let logger: Logger
        private var handlers = [UUID: () -> Void]()
        private let handlersQueue = DispatchQueue(label: "software.micropixels.BatFi.PowerSourceClient.Observer")

        init(logger: Logger) {
            self.logger = logger
            setUpObserving()
        }

        func setUpObserving() {
            let context = Unmanaged.passUnretained(self).toOpaque()
            let loop: CFRunLoopSource = IOPSNotificationCreateRunLoopSource(
                {
                    context in
                    if let context {
                        let observer = Unmanaged<Observer>.fromOpaque(context).takeUnretainedValue()
                        observer.updateBatteryState()
                    }
                },
                context
            ).takeRetainedValue() as CFRunLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, CFRunLoopMode.commonModes)
        }

        func updateBatteryState() {
            logger.debug("New power state")
            handlersQueue.sync { [weak self] in
                self?.handlers.values.forEach { $0() }
            }
        }

        func removeHandler(_ id: UUID) {
            handlersQueue.sync { [weak self] in
                _ = self?.handlers.removeValue(forKey: id)
            }
        }

        func addHandler(_ handler: @escaping () -> Void) -> UUID {
            let id = UUID()
            handlersQueue.sync { [weak self] in
                self?.handlers[id] = handler
            }
            return id
        }
    }
}

private actor BatteryHealthState {
    var lastBatteryHealth: BatteryHealth?

    func setBatteryHealth(_ batteryHealth: BatteryHealth) {
        lastBatteryHealth = batteryHealth
    }
}

private struct BatteryHealth {
    let health: Int
    let date: Date
}
