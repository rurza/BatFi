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
    public static let liveValue: ChargingClient = {
        let logger = Logger(category: "🪫🔋")

        func createClient() -> XPCClient {
            XPCClient.forMachService(
                named: Constant.helperBundleIdentifier,
                withServerRequirement: try! .sameTeamIdentifier
            )
        }

        var reinstallHelperCounter = 0

        func installHelperIfPossibleForError<Result>(
            _ error: Error,
            call: @escaping () async  throws -> Result
        ) async throws -> Result {
            logger.error("Helper error: \(error)")
            let maxAdditionalDelayDuration = 3
            if let error = error as? XPCError {
                switch error {
                case .connectionInvalid, .insecure:
                    do {
                        logger.debug("Trying to fix xpc communication")
                        do {
                            try await HelperManager.liveValue.removeHelper()
                            logger.notice("Service removed. Waiting for \(1 + reinstallHelperCounter)s")
                        } catch {
                            logger.error("Service removal failed")
                            logger.error("\(error.localizedDescription)")
                        }
                        try? await Task.sleep(for: .seconds(1 + reinstallHelperCounter))
                        do {
                            try await HelperManager.liveValue.installHelper()
                            logger.notice("Service installed")
                        } catch {
                            logger.error("Service installation failed")
                            logger.error("\(error.localizedDescription)")
                        }
                        // if installation throws then ignore the error and move on
                        if reinstallHelperCounter < maxAdditionalDelayDuration {
                            reinstallHelperCounter += 1
                        }
                        let result = try await call()
                        reinstallHelperCounter = 0
                        return result
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
                try await createClient().sendMessage(
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
                try await createClient().sendMessage(
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
                try await createClient().sendMessage(
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
                return try await createClient().sendMessage(SMCStatusCommand.status, to: XPCRoute.smcStatus)
            } catch {
                return try await installHelperIfPossibleForError(
                    error,
                    call: chargingStatus
                )
            }
        }

        func quit() async throws {
            logger.debug("Should quit the helper")
            do {
                try await createClient().send(to: XPCRoute.quit)
                logger.notice("Helper did quit")
            } catch { }
        }

        let client = ChargingClient(
            turnOnAutoChargingMode: turnOnAutoChargingModel,
            inhibitCharging: inhibitCharging,
            forceDischarge: forceDischarge,
            chargingStatus: chargingStatus,
            quitChargingHelper: quit,
            resetChargingMode: {
                logger.debug("Should reset the charging mode")
                do {
                    try await createClient().sendMessage(SMCChargingCommand.auto, to: XPCRoute.charging)
                    logger.notice("Did reset the charging")
                } catch {
                    logger.error("Failed to reset the charging mode")
                }
            }
        )
        return client
    }()
}
