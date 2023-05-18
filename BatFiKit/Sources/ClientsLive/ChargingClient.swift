//
//  ChargingClient+Live.swift
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

extension ChargingClient: DependencyKey {
    public static var liveValue: ChargingClient = {
        let logger = Logger(category: "🪫🔋")
        let xpcClient = XPCClient.forMachService(
            named: Constant.helperBundleIdentifier,
            withServerRequirement: try! .sameTeamIdentifier
        )

        func installHelperIfPossibleForError<Result>(
            _ error: Error,
            call: @escaping () async  throws -> Result
        ) async throws -> Result {
            if let error = error as? XPCError {
                switch error {
                case .connectionInvalid, .insecure, .connectionInterrupted:
                    do {
                        logger.debug("Trying to fix xpc communication")
                        await HelperManager.liveValue.removeHelper()
                        logger.debug("Service removed")
                        try await Task.sleep(for: .seconds(1))
                        await HelperManager.liveValue.installHelper()
                        logger.debug("Service installed")
                        try await Task.sleep(for: .seconds(1))
                        return try await call()
                    } catch { }
                default:
                    break
                }
            }
            throw error
        }

        func turnOnAutoChargingModel() async throws {
            logger.debug("Should send \(#function)")
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
            logger.debug("Should send \(#function)")
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
            logger.debug("Should send \(#function)")
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
            logger.debug("Should send \(#function)")
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
            logger.debug("Should send \(#function)")
            do {
                try await xpcClient.send(to: XPCRoute.quit)
            } catch {
                try await installHelperIfPossibleForError(error, call: quit)
            }
        }

        let client = ChargingClient(
            turnOnAutoChargingMode: turnOnAutoChargingModel,
            inhibitCharging: inhibitCharging,
            forceDischarge: forceDischarge,
            chargingStatus: chargingStatus,
            quitChargingHelper: quit
        )
        return client
    }()
}
