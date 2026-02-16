//
//  Listener.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Foundation
import os
import Shared

private struct UnsafeSendableBox<T>: @unchecked Sendable {
    let value: T
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: XPCService.self)
        newConnection.exportedObject = XPCServiceHandler()
        newConnection.resume()
        return true
    }
}

final class XPCServiceHandler: NSObject, XPCService, @unchecked Sendable {
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

    func getCurrentChargingStatus(_ reply: @escaping (Shared.SMCChargingStatus?, (any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                let status = try await smcService.smcChargingStatus()
                reply.value(status, nil)
            } catch {
                logger.error("Error getting current charging status: \(error)")
                reply.value(nil, error)
            }
        }
    }

    func getPowerDistribution(_ reply: @escaping (Shared.PowerDistributionInfo?, (any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                let info = try await smcService.getPowerDistribution()
                reply.value(info, nil)
            } catch {
                logger.error("Error getting power distribution: \(error)")
                reply.value(nil, error)
            }
        }
    }

    func setMagSafeLEDColor(color: UInt8, _ reply: @escaping (UInt8, (any Error)?) -> Void) {
        logger.notice("\(#function, privacy: .public)")
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                guard let magSafeLEDOption = MagSafeLEDOption(rawValue: color) else {
                    throw NSError(domain: Constant.helperBundleIdentifier, code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid MagSafe LED color"])
                }
                let option = try await smcService.magsafeLEDColor(magSafeLEDOption)
                reply.value(option.rawValue, nil)
            } catch {
                logger.error("Error setting MagSafe LED color: \(error)")
                reply.value(UInt8.max, error)
            }
        }
    }

    func getMagSafeLEDOption(_ handler: @escaping (UInt8, (any Error)?) -> Void) {
        let handler = UnsafeSendableBox(value: handler)
        Task {
            do {
                let option = try await smcService.magsafeLEDColor()
                handler.value(option.rawValue, nil)
            } catch {
                logger.error("Error getting MagSafe LED color: \(error)")
                handler.value(UInt8.max, error)
            }
        }
    }

    func ping(_ reply: @escaping (Bool, Error?) -> Void) {
        reply(true, nil)
    }

    func quit(_ reply: @escaping (Bool, Error?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            await smcService.close()
            reply.value(true, nil)
            try? await Task.sleep(for: .milliseconds(100))
            exit(0)
        }
    }

    func turnPowerMode(_ mode: UInt8, lowPowerModeOnly: Bool, _ handler: @escaping ((any Error)?) -> Void) {
        let handler = UnsafeSendableBox(value: handler)
        Task {
            let process = Process()
            process.launchPath = "/usr/bin/pmset"
            process.arguments = ["-a", (lowPowerModeOnly ? "lowpowermode" : "powermode"), mode.description]
            process.launch()
            process.waitUntilExit()
            handler.value(nil)
        }
    }

    func currentPowerMode(_ handler: @escaping (NSNumber?, Bool) -> Void) {
        let handler = UnsafeSendableBox(value: handler)
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

            func newPmset(output: Pipe) -> Process {
                let pmsetProcess = Process()
                // Configure the `pmset` process
                pmsetProcess.launchPath = "/usr/bin/pmset"
                pmsetProcess.arguments = ["-g"]
                pmsetProcess.standardOutput = output
                return pmsetProcess
            }

            func newGrep(input: Pipe, output: Pipe, argument: String) -> Process {
                let grepProcess = Process()
                grepProcess.launchPath = "/usr/bin/grep"
                grepProcess.arguments = ["-w", argument]
                grepProcess.standardInput = input
                grepProcess.standardOutput = output
                return grepProcess
            }

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let pmsetProcess = newPmset(output: inputPipe)
            let grepProcess = newGrep(input: inputPipe, output: outputPipe, argument: "powermode")
            do {
                try pmsetProcess.run()
                try grepProcess.run()
            } catch {
                handler.value(nil, false)
            }
            pmsetProcess.waitUntilExit()
            grepProcess.waitUntilExit()

            // Read the output from the `grep` process
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8),
               let result = parsePowerMode(output: output) {
                handler.value(NSNumber(value: result), true)
            } else {
                let inputPipe = Pipe()
                let outputPipe = Pipe()
                let pmsetProcess = newPmset(output: inputPipe)
                let grepProcess = newGrep(input: inputPipe, output: outputPipe, argument: "powermode")
                do {
                    try pmsetProcess.run()
                    try grepProcess.run()
                } catch {
                    handler.value(nil, false)
                }
                pmsetProcess.waitUntilExit()
                grepProcess.waitUntilExit()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: outputData, encoding: .utf8),
                let result = parsePowerMode(output: output) else {
                    handler.value(nil, false)
                    return
                }
                handler.value(NSNumber(value: result), false)
            }
        }
    }

    func disableAutosleep(_ disable: Bool, _ handler: @escaping (Error?) -> Void) {
        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-a", "disablesleep", disable ? "1" : "0"]
        do {
            try process.run()
        } catch {
            handler(error)
        }
        process.waitUntilExit()
        handler(nil)
    }

    // MARK: - Priv

    private func changeChargingMode(_ newMode: SMCChargingCommand, reply: @escaping (Error?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                try await smcService.setChargingMode(newMode)
                reply.value(nil)
            } catch {
                logger.error("Error changing charging mode \(newMode.rawValue, privacy: .public): \(error, privacy: .public)")
                reply.value(error)
            }
        }
    }

}
