//
//  Time.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Foundation


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
