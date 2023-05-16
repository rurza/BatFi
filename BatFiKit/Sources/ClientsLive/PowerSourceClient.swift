//
//  PowerSourceClient+Live.swift
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
    public static var liveValue: PowerSourceClient = {
        let logger = Logger(category: "⚡️")
        let observer = Observer(logger: logger)
        let client = PowerSourceClient(
            powerSourceChanges: {
                AsyncStream { continuation in
                    if let initialState = try? getPowerSourceInfo() {
                        continuation.yield(initialState)
                    }
                    observer.handlers.append(
                        {
                            if let powerState = try? getPowerSourceInfo() {
                                continuation.yield(powerState)
                            } else {
                                logger.error("New power state, but there is an info missing")
                            }
                        }
                    )
                }
            },
            currentPowerSourceState: {
                let state = try getPowerSourceInfo()
                logger.debug("Power state: \(state, privacy: .public)")
                return state
            }
        )

        return client
    }()

    private class Observer {
        let logger: Logger
        var handlers = [() -> Void]()

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
            handlers.forEach { $0() }
        }
    }
}

private func getPowerSourceInfo() throws -> PowerState {
    func getIntValue(_ identifier: CFString, from service: io_service_t) -> Int? {
        if let value = IORegistryEntryCreateCFProperty(service, identifier, kCFAllocatorDefault, 0) {
            let int = value.takeUnretainedValue() as? Int
            value.release()
            return int
        }

        return nil
    }

    func getStringValue(_ identifier: CFString, from service: io_service_t) -> String? {
        if let value = IORegistryEntryCreateCFProperty(service, identifier, kCFAllocatorDefault, 0) {
            let string = value.takeUnretainedValue() as? String
            value.release()
            return string
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
    let batteryHealth = info[kIOPSBatteryHealthKey] as? String

    guard
        let batteryLevel,
        let isCharging,
        let powerSource,
        let timeLeft,
        let timeToCharge,
        let batteryHealth else {
        throw PowerSourceError.infoMissing
    }

    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    defer {
        IOServiceClose(service)
        IOObjectRelease(service)
    }

    guard
        let cyclesRef = IORegistryEntryCreateCFProperty(
            service,
            kIOPMPSCycleCountKey as CFString,
            kCFAllocatorDefault,
            0
        ),
        let cycleClount = cyclesRef.takeUnretainedValue() as? Int else {
        throw PowerSourceError.infoMissing
    }

    guard
        let temperatureRef = IORegistryEntryCreateCFProperty(
            service,
            kIOPMPSBatteryTemperatureKey as CFString,
            kCFAllocatorDefault,
            0
        ),
        let temperature = temperatureRef.takeUnretainedValue() as? Double else {
        throw PowerSourceError.infoMissing
    }
    let batteryTemperature = temperature / 100

    guard
        let chargerConnectedRef = IORegistryEntryCreateCFProperty(
            service,
            kIOPMPSExternalConnectedKey as CFString,
            kCFAllocatorDefault,
            0
        ),
        let chargerConnected = chargerConnectedRef.takeUnretainedValue() as? Bool else {
        throw PowerSourceError.infoMissing
    }


    let powerState = PowerState(
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        powerSource: powerSource,
        timeLeft: timeLeft,
        timeToCharge: timeToCharge,
        batteryCycleCount: cycleClount,
        batteryHealth: batteryHealth,
        batteryTemperature: batteryTemperature,
        chargerConnected: chargerConnected
    )
    return powerState
}
