//
//  PowerModeClient+Live.swift
//  BatFiKit
//
//  Created by Adam Różyński on 20.11.2024.
//

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
                try await xpcClient.setPowerMode(powerMode.uint, lowPowerModeOnly: lowPowerModeOnly)
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
