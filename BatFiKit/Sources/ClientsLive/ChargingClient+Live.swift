//
//  ChargingClient.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppKit
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import Shared

extension ChargingClient: DependencyKey {
    public static let liveValue: ChargingClient = {
        return Self(
            turnOnAutoChargingMode: {
                try await XPCClient.shared.changeChargingMode(.auto)
            },
            inhibitCharging: {
                try await XPCClient.shared.changeChargingMode(.inhibitCharging)
            },
            forceDischarge: {
                try await XPCClient.shared.changeChargingMode(.forceDischarging)
            },
            restoreSystemDefaults: {
                try await XPCClient.shared.restoreSystemDefaults()
            },
            applyChargeLimit: { percentage in
                try await XPCClient.shared.applyChargeLimit(percentage)
            },
            reassertChargeLimit: { percentage in
                try await XPCClient.shared.reassertChargeLimit(percentage)
            },
            nudgeChargeLimit: { nudgeValue, target in
                try await XPCClient.shared.nudgeChargeLimit(to: nudgeValue, restoring: target)
            },
            chargingStatus: {
                return try await XPCClient.shared.getSMCChargingStatus()
            },
            mclStatus: {
                return try await XPCClient.shared.getMCLStatus()
            },
            chargingDiagnostics: {
                let diagnostics = try await XPCClient.shared.getChargingDiagnostics()
                // The one write site for `lastKnownChargeBackend`. Every pane and sheet that
                // needs this Mac's floor synchronously reads that cache, and putting the
                // refresh here means none of them has to remember to fetch first. A nil
                // result is a helper that answered without a snapshot, which is not evidence
                // the backend changed — so the previous value stands rather than being
                // cleared.
                if let diagnostics {
                    Defaults[.lastKnownChargeBackend] = diagnostics.backend
                }
                return diagnostics
            }
        )
    }()
}
