//
//  Time.swift
//
//
//  Created by Adam on 05/05/2023.
//

import Foundation
import L10n

public struct Time: Equatable {
    public let info: Info
    public let direction: Direction

    public enum Direction: Equatable {
        case timeLeft
        case timeToCharge
    }

    public enum Info: Equatable {
        case claculating
        case unknown
        case time(Int)
    }

    public struct Description {
        public let label: String
        public let description: String
    }

    init(info: Info, direction: Direction) {
        self.info = info
        self.direction = direction
    }

    public var description: Description? {
        let l10n = L10n.BatteryInfo.Label.Main.Time.self
        func infoDescription() -> String? {
            switch info {
            case .claculating:
                return l10n.calculating
            case .unknown:
                return nil
            case let .time(time):
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

    public var hasKnownTime: Bool {
        switch info {
        case .claculating, .unknown:
            return false
        case .time:
            return true
        }
    }

    public init?(isCharging: Bool, timeLeft: Int, timeToCharge: Int, batteryLevel: Int) {
        if isCharging {
            if batteryLevel < 100 {
                direction = .timeToCharge
                if timeToCharge > 0 {
                    info = .time(timeToCharge)
                } else if timeToCharge == 0 {
                    info = .unknown
                } else {
                    info = .claculating
                }
            } else {
                return nil
            }
        } else {
            direction = .timeLeft
            if timeLeft > 0 {
                info = .time(timeLeft)
            } else if timeLeft == 0 {
                info = .unknown
            } else {
                info = .claculating
            }
        }
    }

    public static func timeLeft(time: Int) -> Time {
        let info: Info
        switch time {
        case let time where time > 0:
            info = .time(time)
        case 0:
            info = .unknown
        default:
            info = .claculating
        }
        return Time(info: info, direction: .timeLeft)
    }
}
