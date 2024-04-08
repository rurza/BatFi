//
//  Listener.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Foundation
import os
import Shared

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: XPCService.self)
        newConnection.exportedObject = XPCServiceHandler()
        newConnection.resume()
        return true
    }
}

final class XPCServiceHandler: XPCService {
    private lazy var logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "XPCServiceHandler")
    private lazy var smcService = SMCService()

    func setForceDischarge(_ reply: @escaping ((any Error)?) -> Void) {
        changeChargingMode(.forceDischarging, reply: reply)
    }
    
    func setInhibitCharge(_ reply: @escaping ((any Error)?) -> Void) {
        changeChargingMode(.inhibitCharging, reply: reply)
    }
    
    func setAutocharge(_ reply: @escaping ((any Error)?) -> Void) {
        changeChargingMode(.auto, reply: reply)
    }

    func setEnableSystemChargeLimit(_ handler: @escaping ((any Error)?) -> Void) {
        changeChargingMode(.enableSystemChargeLimit, reply: handler)
    }

    private func changeChargingMode(_ newMode: SMCChargingCommand, reply: @escaping (Error?) -> Void) {
        logger.notice("Changing charging mode: \(newMode.rawValue, privacy: .public)")
        Task {
            do {
                try await smcService.setChargingMode(newMode)
                reply(nil)
            } catch {
                logger.error("Error changing charging mode \(newMode.rawValue, privacy: .public): \(error, privacy: .public)")
                reply(error)
            }
        }
    }

    func getCurrentChargingStatus(_ reply: @escaping (Shared.SMCChargingStatus?, (any Error)?) -> Void) {
        logger.notice("\(#function, privacy: .public)")
        Task {
            do {
                let status = try await smcService.smcChargingStatus()
                reply(status, nil)
            } catch {
                logger.error("Error getting current charging status: \(error)")
                reply(nil, error)
            }
        }
    }

    func getPowerDistribution(_ reply: @escaping (Shared.PowerDistributionInfo?, (any Error)?) -> Void) {
        logger.notice("\(#function, privacy: .public)")
        Task {
            do {
                let info = try await smcService.getPowerDistribution()
                reply(info, nil)
            } catch {
                logger.error("Error getting power distribution: \(error)")
                reply(nil, error)
            }
        }
    }
    
    func setMagSafeLEDColor(color: UInt8, _ reply: @escaping (UInt8, (any Error)?) -> Void) {
        logger.notice("\(#function, privacy: .public)")
        Task {
            do {
                guard let magSafeLEDOption = MagSafeLEDOption(rawValue: color) else {
                    throw NSError(domain: Constant.helperBundleIdentifier, code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid MagSafe LED color"])
                }
                let option = try await smcService.magsafeLEDColor(magSafeLEDOption)
                reply(option.rawValue, nil)
            } catch {
                logger.error("Error setting MagSafe LED color: \(error)")
                reply(UInt8.max, error)
            }
        }
    }    

    func ping(_ reply: @escaping (Bool, Error?) -> Void) {
        reply(true, nil)
    }

    func quit(_ reply: @escaping (Bool, Error?) -> Void) {
        Task {
            await smcService.close()
            reply(true, nil)
            try? await Task.sleep(for: .milliseconds(100))
            exit(0)
        }
    }

}
