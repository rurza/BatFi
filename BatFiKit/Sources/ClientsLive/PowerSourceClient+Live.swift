//
//  PowerSourceClient.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Clients
import Combine
import Dependencies
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import os
import Shared

extension PowerSourceClient: DependencyKey {
    public static let liveValue: PowerSourceClient = {
        let logger = Logger(category: "Power Source")
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

        let observer = Observer(getPowerSourceInfo: getPowerSourceInfo)


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

                    let cancellable = observer.subject
                        .sink { powerState in
                            Task {
                                continuation.yield(powerState)
                            }
                        }

                    continuation.onTermination = { _ in
                        cancellable.cancel()
                    }
                }
            },
            currentPowerSourceState: {
                try await getPowerSourceInfo()
            },
            isRunningOnLaptop: {
                if let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                   let powerSourcesList = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef] {
                    // Check if any power source has a battery
                    for powerSource in powerSourcesList {
                        if let description = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
                           let type = description[kIOPSTypeKey] as? String,
                           type == kIOPSInternalBatteryType {
                            return true // A built-in battery is found, indicating a laptop
                        }
                    }
                }
                return false // No internal battery found, likely a desktop Mac
            }
        )

        return client
    }()

    private class Observer {
        let getPowerSourceInfo: () async throws -> PowerState
        let subject = PassthroughSubject<PowerState, Never>()
        private lazy var logger = Logger(category: "PowerSourceClienty.Observer")

        init(getPowerSourceInfo: @escaping () async throws -> PowerState) {
            self.getPowerSourceInfo = getPowerSourceInfo
            setUpObserving()
        }

        func setUpObserving() {
            let context = Unmanaged.passUnretained(self).toOpaque()
            let loop: CFRunLoopSource = IOPSNotificationCreateRunLoopSource(
                {
                    context in
                    if let context {
                        let observer = Unmanaged<Observer>.fromOpaque(context).takeUnretainedValue()
                        observer.logger.debug("Power state did change.")
                        Task {
                            do {
                                let powerState = try await observer.getPowerSourceInfo()
                                observer.logger.debug("New power state: \(powerState)")
                                observer.subject.send(powerState)
                            } catch {
                                observer.logger.error("")
                            }
                        }
                    }
                },
                context
            ).takeRetainedValue() as CFRunLoopSource
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, CFRunLoopMode.commonModes)
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
