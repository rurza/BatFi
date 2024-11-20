//
//  PowerModeClient+Live.swift
//  BatFiKit
//
//  Created by Adam Różyński on 20.11.2024.
//

import Foundation
import Clients
import Dependencies

extension PowerModeClient {
    public static let live: Self = {
        let xpcClient = XPCClient.shared
        return Self(
            getCurrentPowerMode: {
                let uint = try await xpcClient.getPowerMode()
                if let mode = PowerMode(uint: uint) {
                    return mode
                } else {
                    throw PowerModeClientError.unsupportedMode
                }
            },
            setPowerMode: { powerMode in
                try await xpcClient.setPowerMode(powerMode.uint)
            }
        )
    }()
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
