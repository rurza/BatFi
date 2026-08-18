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

    private static let pmset = "/usr/bin/pmset"
    /// `pmset` answers in milliseconds; this only bounds a wedged one. It runs as root here,
    /// so an unbounded wait would strand a root process rather than merely a slow reply.
    private static let pmsetTimeout: Duration = .seconds(10)

    private static func pmsetError(_ description: String) -> NSError {
        NSError(
            domain: Constant.helperBundleIdentifier,
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

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

    func reassertChargeLimit(_ percentage: UInt8, _ reply: @escaping (UInt8, (any Error)?) -> Void) {
        let reply = UnsafeSendableBox(value: reply)
        Task {
            do {
                let applied = try await smcService.reassertChargeLimit(Int(percentage))
                guard let appliedByte = UInt8(exactly: applied), appliedByte <= 100 else {
                    throw NSError(
                        domain: Constant.helperBundleIdentifier,
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Reasserted charge limit \(applied) is not a percentage"]
                    )
                }
                reply.value(appliedByte, nil)
            } catch {
                logger.error("Error reasserting charge limit \(percentage, privacy: .public)%: \(error, privacy: .public)")
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
            let key = lowPowerModeOnly ? "lowpowermode" : "powermode"
            guard await Subprocess.run(
                Self.pmset,
                arguments: ["-a", key, mode.description],
                timeout: Self.pmsetTimeout
            ) else {
                logger.error("Could not set \(key, privacy: .public) to \(mode, privacy: .public)")
                handler.value(Self.pmsetError("Could not set \(key)"))
                return
            }
            handler.value(nil)
        }
    }

    func currentPowerMode(_ handler: @escaping (NSNumber?, Bool) -> Void) {
        let handler = UnsafeSendableBox(value: handler)
        Task {
            func readPowerMode() async -> UInt8? {
                guard let output = await Subprocess.standardOutput(
                    of: Self.pmset,
                    arguments: ["-g"],
                    timeout: Self.pmsetTimeout
                ) else { return nil }
                return PmsetOutput.value(forKey: "powermode", in: output)
            }

            if let mode = await readPowerMode() {
                handler.value(NSNumber(value: mode), true)
                return
            }

            // The second look is carried over verbatim, including the part that looks wrong.
            //
            // Both attempts read the same key, so the retry can only change the answer if
            // the first `pmset` failed transiently — yet succeeding on the retry reports
            // `false` for the flag the app reads as "high power mode is available", which
            // is not a claim a retry can support. The shape of the code it replaced says
            // what was meant: the lookup was factored into a function taking the key as a
            // parameter, and then called twice with the same one. The second was almost
            // certainly meant to ask for `lowpowermode`, which is the key Macs without high
            // power mode publish instead, and would make the flag mean what its name says.
            //
            // Left alone because it cannot be checked here: this Mac publishes `powermode`,
            // so the branch that matters never runs on it. The user-visible outcome is also
            // the same either way today — the app's only reader treats a thrown error and a
            // `false` flag identically, showing "High power mode is not supported" — so
            // guessing buys nothing and risks a wrong answer on hardware nobody tested.
            guard let mode = await readPowerMode() else {
                logger.error("Could not read powermode from pmset")
                handler.value(nil, false)
                return
            }
            handler.value(NSNumber(value: mode), false)
        }
    }

    func disableAutosleep(_ disable: Bool, _ handler: @escaping (Error?) -> Void) {
        let handler = UnsafeSendableBox(value: handler)
        Task {
            guard await Subprocess.run(
                Self.pmset,
                arguments: ["-a", "disablesleep", disable ? "1" : "0"],
                timeout: Self.pmsetTimeout
            ) else {
                logger.error("Could not set disablesleep to \(disable, privacy: .public)")
                handler.value(Self.pmsetError("Could not set disablesleep"))
                return
            }
            handler.value(nil)
        }
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
