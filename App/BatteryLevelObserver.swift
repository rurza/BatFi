//
//  BatteryLevelObserver.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import Foundation
import IOKit.ps

final class BatteryLevelObserver: ObservableObject {
    @Published var batteryLevel: Int?
    @Published var isCharging: Bool?

    private var timer: Timer?

    init() {
        updateBatteryState()
        setUpTimer()
    }

    func setUpTimer() {
        let batteryLevel = self.batteryLevel ?? 0
        let timerInterval: TimeInterval
        if batteryLevel < 20 {
            timerInterval = 2
        } else if batteryLevel >= 20 && batteryLevel < 60 {
            timerInterval = 5
        } else if batteryLevel >= 60 && batteryLevel < 80 {
            timerInterval = 10
        } else {
            timerInterval = 20
        }
        timer = Timer.scheduledTimer(
            withTimeInterval: timerInterval,
            repeats: false,
            block: { [weak self] timer in
                self?.updateBatteryState()
                timer.invalidate()
                self?.setUpTimer()
            }
        )
    }

    func updateBatteryState() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeUnretainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeUnretainedValue() as Array
        let info = IOPSGetPowerSourceDescription(snapshot, sources[0]).takeUnretainedValue() as! [String: AnyObject]

        print(sources)

        let batteryLevel = info[kIOPSCurrentCapacityKey] as? Int
        let isCharging = info[kIOPSIsChargingKey] as? Bool
        let powerSource = info[kIOPSPowerSourceStateKey] as? String
        let temperature = info[kIOPSTemperatureKey]
        let timeLeft = info[kIOPSTimeToEmptyKey] as? Int

        if let isCharging, isCharging != self.isCharging {
            self.isCharging = isCharging
        }
        if let batteryLevel, batteryLevel != self.batteryLevel {
            self.batteryLevel = batteryLevel
        }
        if let powerSource {
            if powerSource == kIOPSBatteryPowerValue {

            } else if powerSource == kIOPSACPowerValue {

            } else {

            }
        }
        print(isCharging, batteryLevel, powerSource, temperature, timeLeft)
    }
}
