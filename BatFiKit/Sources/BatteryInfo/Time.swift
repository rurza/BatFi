//
//  Time.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import AppShared
import Foundation
import L10n

struct Time: Equatable {
    let info: Info
    let direction: Direction

    enum Direction: Equatable {
        case timeLeft
        case timeToCharge
    }

    enum Info: Equatable {
        case claculating
        case unknown
        case time(Int)
    }

    struct Description {
        let label: String
        let description: String
    }

    var description: Description? {
        let l10n = L10n.BatteryInfo.Label.Main.Time.self
        func infoDescription() -> String? {
            switch info {
            case .claculating:
                return l10n.calculating
            case .unknown:
                return nil
            case .time(let time):
                let interval = Double(time) * 60
                return timeFormatter.string(from: interval)!
            }
        }
        if let infoDescription = infoDescription() {
            switch direction {
            case .timeLeft:
                return Description(label: l10n.timeLeft, description: infoDescription)
            case .timeToCharge:
                return Description(label: l10n.timeToCharge, description: infoDescription)
            }
        } else {
            return nil
        }
    }

    var hasKnownTime: Bool {
        switch info {
        case .claculating, .unknown:
            return false
        case .time:
            return true
        }
    }

    init?(isCharging: Bool, timeLeft: Int, timeToCharge: Int, batteryLevel: Int) {
        if isCharging {
            if batteryLevel < 100 {
                self.direction = .timeToCharge
                if timeToCharge > 0 {
                    self.info = .time(timeToCharge)
                } else if timeToCharge == 0 {
                    self.info = .unknown
                } else {
                    self.info = .claculating
                }
            } else {
                return nil
            }
        } else {
            self.direction = .timeLeft
            if timeLeft > 0 {
                self.info = .time(timeLeft)
            } else if timeLeft == 0 {
                self.info = .unknown
            } else {
                self.info = .claculating
            }
        }
    }
}
