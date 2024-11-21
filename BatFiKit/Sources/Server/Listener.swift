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
    private lazy var smcService = SMCService.shared

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

    func getMagSafeLEDOption(_ handler: @escaping (UInt8, (any Error)?) -> Void) {
        Task {
            do {
                let option = try await smcService.magsafeLEDColor()
                handler(option.rawValue, nil)
            } catch {
                logger.error("Error getting MagSafe LED color: \(error)")
                handler(UInt8.max, error)
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

    func turnPowerMode(_ mode: UInt8, _ handler: @escaping ((any Error)?) -> Void) {
        Task {
            let process = Process()
            process.launchPath = "/usr/bin/pmset"
            process.arguments = ["-a", "powermode", mode.description]
            process.launch()
            process.waitUntilExit()
            handler(nil)
        }
    }

    func currentPowerMode(_ handler: @escaping (NSNumber?, Bool) -> Void) {
        Task {
            func parsePowerMode(output: String) -> UInt8? {
                // Extract the value by trimming spaces and suffixing the last character
                let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if let lastSpaceIndex = trimmedOutput.lastIndex(of: " ") {
                    let valueStartIndex = trimmedOutput.index(after: lastSpaceIndex)
                    if let uint = UInt8(trimmedOutput[valueStartIndex...]) {
                        return uint
                    }
                }
                return nil
            }
            let pmsetProcess = Process()
            let grepProcess = Process()
            let pipe1 = Pipe()
            let pipe2 = Pipe()

            // Configure the `pmset` process
            pmsetProcess.launchPath = "/usr/bin/pmset"
            pmsetProcess.arguments = ["-g"]
            pmsetProcess.standardOutput = pipe1

            // Configure the `grep` process
            grepProcess.launchPath = "/usr/bin/grep"
            grepProcess.arguments = ["powermode"]
            grepProcess.standardInput = pipe1
            grepProcess.standardOutput = pipe2

            // Launch the processes
            pmsetProcess.launch()
            grepProcess.launch()

            // Wait for the processes to complete
            pmsetProcess.waitUntilExit()
            grepProcess.waitUntilExit()

            // Read the output from the `grep` process
            let outputData = pipe2.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8) else {
                let anotherGrepProcess = Process()
                let pipe3 = Pipe()
                // Configure the `grep` process
                anotherGrepProcess.launchPath = "/usr/bin/grep"
                anotherGrepProcess.arguments = ["lowpowermode"]
                anotherGrepProcess.standardInput = pipe1
                anotherGrepProcess.standardOutput = pipe3
                let outputData = pipe3.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: outputData, encoding: .utf8),
                let result = parsePowerMode(output: output) else {
                    handler(nil, false)
                    return
                }
                handler(NSNumber(value: result), false)
                return
            }
            guard let result = parsePowerMode(output: output) else {
                handler(nil, false)
                return
            }
            handler(NSNumber(value: result), true)
        }
    }

}
