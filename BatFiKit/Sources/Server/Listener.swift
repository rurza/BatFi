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
    private lazy var logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "ListenerDelegate")

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: XPCService.self)
        newConnection.exportedObject = XPCServiceHandler()

        // The client's pid is read here, on the accept, because this is the one moment the
        // process is provably alive — which is what makes the watch armed from it race-free.
        //
        // That watch, not this connection, is how the helper learns the app is gone. It
        // survives every way an app can die and needs no cooperation from it: a crash, a
        // jetsam kill, a force-quit, an installer's `SIGKILL`, or simply a quit message that
        // was never sent because the app's terminate watchdog won the race first. That last
        // one is not hypothetical — it is what left a stale helper bound to the mach service
        // across an in-place update, so the relaunched app was routed to the previous build.
        let pid = newConnection.processIdentifier
        let connectionID = HelperShutdownPolicy.ConnectionID()
        logger.notice("Accepted a connection from pid \(pid, privacy: .public)")
        HelperShutdown.shared.handle(.clientConnected(connectionID, pid: pid))

        // Reported, and deliberately not acted on. A connection dying proves nothing about
        // the app: `XPCClient` tears one down on purpose whenever a call goes unanswered and
        // builds a replacement on the next call. Restoring here — which is what this used to
        // do once the count reached zero — releases the firmware charge band under an app
        // that is still running and still asking for it.
        newConnection.invalidationHandler = {
            HelperShutdown.shared.handle(.connectionInvalidated(connectionID))
        }
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

    func restoreSystemDefaults(_ reply: @escaping ((any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                try await smcService.restoreSystemDefaults()
                reply.value(nil)
            } catch {
                logger.error("Error restoring system defaults: \(error, privacy: .public)")
                reply.value(error)
            }
        }
    }

    func applyChargeLimit(_ percentage: UInt8, _ reply: @escaping (UInt8, (any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                let applied = try await smcService.applyChargeLimit(Int(percentage))
                // The reply's failure sentinel is UInt8.max, so anything that is not a
                // percentage has to fail loudly here rather than travel as one. Nothing
                // downstream can produce such a value today; this is what keeps that true.
                guard let appliedByte = UInt8(exactly: applied), appliedByte <= 100 else {
                    throw NSError(
                        domain: Constant.helperBundleIdentifier,
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Applied charge limit \(applied) is not a percentage"]
                    )
                }
                reply.value(appliedByte, nil)
            } catch {
                logger.error("Error applying charge limit \(percentage, privacy: .public)%: \(error, privacy: .public)")
                reply.value(UInt8.max, error)
            }
        }
    }

    func getMCLStatus(_ reply: @escaping (Shared.MCLStatus?, (any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            let status = await smcService.mclStatus()
            reply.value(status, nil)
        }
    }

    func getChargingDiagnostics(_ reply: @escaping (Shared.ChargingDiagnostics?, (any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            let diagnostics = await smcService.chargingDiagnostics()
            reply.value(diagnostics, nil)
        }
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

    /// Restores *before* replying, and this ordering is load-bearing in both directions.
    ///
    /// `SMCService.close()` only drops the SMC connection — it hands nothing back. Until now
    /// the restore on this path happened entirely through `ListenerDelegate`'s invalidation
    /// handler, on the way out. That handler no longer restores, so this has to, or
    /// `HelperConnectionManager.takeOwnership()` stops releasing the firmware charge band it
    /// evicts a foreign helper specifically to release.
    ///
    /// And the reply has to come after, not before: the caller treats it as proof the helper
    /// is finished, and on the app's own quit path terminates the moment it lands. A restore
    /// still running past that point would be racing Sparkle's relaunch for the mach
    /// service, which is the failure this whole path exists to prevent.
    func quit(_ reply: @escaping (Bool, Error?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            // Does not return: `HelperShutdown` restores, runs this, and exits.
            await HelperShutdown.shared.handle(.quitRequested) {
                await SMCService.shared.close()
                reply.value(true, nil)
                // The reply is written to the connection asynchronously, so exiting on the
                // same turn can truncate it. Nothing depends on it arriving any more — a
                // missed reply now costs the caller a timeout rather than a leaked root
                // process — but a clean answer is still worth 100ms.
                try? await Task.sleep(for: .milliseconds(100))
            }
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
