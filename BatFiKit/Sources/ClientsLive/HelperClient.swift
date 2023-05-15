//
//  HelperClient+Live.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Clients
import Cocoa
import Dependencies
import IOKit.pwr_mgt
import os
import SecureXPC
import Shared

extension HelperClient: DependencyKey {
    public static var liveValue: HelperClient = {
        let logger = Logger(category: "🪫🔋")
        let xpcClient = XPCClient.forMachService(
            named: Constant.helperBundleIdentifier,
            withServerRequirement: try! .sameTeamIdentifier
        )

        func installHelperIfPossibleForError<Result>(
            _ error: Error,
            call: @escaping () async  throws -> Result
        ) async throws -> Result {
            if let error = error as? XPCError, case .insecure = error {
                do {
                    logger.debug("Trying to fix xpc communication")
                    try HelperManager.shared.removeService()
                    logger.debug("Service removed")
                    try await Task.sleep(for: .seconds(1))
                    try HelperManager.shared.registerService()
                    logger.debug("Service installed")
                    return try await call()
                } catch { }

            }
            throw error
        }

        func turnOnAutoChargingModel() async throws {
            do {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.auto,
                    to: XPCRoute.charging
                )
            } catch {
                try await installHelperIfPossibleForError(
                    error,
                    call: turnOnAutoChargingModel
                )
            }
        }

        func inhibitCharging() async throws {
            do {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.inhibitCharging,
                    to: XPCRoute.charging
                )
            } catch {
                try await installHelperIfPossibleForError(
                    error,
                    call: inhibitCharging
                )
            }
        }

        func forceDischarge() async throws {
            do {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.forceDischarging,
                    to: XPCRoute.charging
                )
            } catch {
                try await installHelperIfPossibleForError(error, call: forceDischarge)
            }
        }

        func chargingStatus() async throws -> SMCStatus {
            do {
                return try await xpcClient.sendMessage(SMCStatusCommand.status, to: XPCRoute.smcStatus)
            } catch {
                return try await installHelperIfPossibleForError(
                    error,
                    call: chargingStatus
                )
            }
        }

        func quit() async throws {
            do {
                try await xpcClient.send(to: XPCRoute.quit)
            } catch {
                try await installHelperIfPossibleForError(error, call: quit)
            }
        }

        let client = HelperClient(
            turnOnAutoChargingMode: turnOnAutoChargingModel,
            inhibitCharging: inhibitCharging,
            forceDischarge: forceDischarge,
            chargingStatus: chargingStatus,
            quitChargingHelper: quit
        )
        return client
    }()
}
