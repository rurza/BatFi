//
//  BatteryLevelObserver.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import Foundation
import IOKit.ps
import os

final class BatteryLevelObserver: ObservableObject {
    private(set) var batteryLevel: Int?
    private(set) var isCharging: Bool?
    private(set) var powerSource: String?
    private(set) var timeLeftString: String?
    private(set) var timeLeft: Int? {
        didSet {
            if let timeLeft, timeLeft > 0 {
                let interval = Double(timeLeft) * 60
                timeLeftString = timeFormatter.string(from: interval)!
            } else {
                timeLeftString = nil
            }
        }
    }
    private lazy var logger = Logger(category: "⚡️")

    private lazy var timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    static let shared = BatteryLevelObserver()

    init() {
        updateBatteryState()
        setUpObserving()
    }

    func setUpObserving() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let loop: CFRunLoopSource = IOPSNotificationCreateRunLoopSource(
            {
                context in
                if let context {
                    let observer = Unmanaged<BatteryLevelObserver>.fromOpaque(context).takeUnretainedValue()
                    observer.updateBatteryState()
                }
            },
            context
        ).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.commonModes)
    }

    func updateBatteryState() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeUnretainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeUnretainedValue() as Array
        let info = IOPSGetPowerSourceDescription(snapshot, sources[0]).takeUnretainedValue() as! [String: AnyObject]

        let batteryLevel = info[kIOPSCurrentCapacityKey] as? Int
        let isCharging = info[kIOPSIsChargingKey] as? Bool
        let powerSource = info[kIOPSPowerSourceStateKey] as? String
        let timeLeft = info[kIOPSTimeToEmptyKey] as? Int

        if let isCharging, isCharging != self.isCharging {
            self.isCharging = isCharging
        }
        if let batteryLevel, batteryLevel != self.batteryLevel {
            self.batteryLevel = batteryLevel
        }
        if let powerSource, powerSource != self.powerSource {
            self.powerSource = powerSource
        }
        if let timeLeft, self.timeLeft != timeLeft {
            if isCharging == true || powerSource == kIOPSBatteryPowerValue {
                self.timeLeft = timeLeft
            } else {
                self.timeLeft = nil
            }
        }
        logger.debug("State updated: \n- is charging: \(isCharging ?? false),\n- battery level: \(batteryLevel ?? -1),\n- power source: \(powerSource ?? "not known"),\n- time left: \(self.timeLeftString ?? "not known")")
        objectWillChange.send()
    }
}
