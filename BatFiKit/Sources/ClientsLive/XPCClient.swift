//
//  XPCClient.swift
//
//
//  Created by Adam Różyński on 26/03/2024.
//

import AsyncXPCConnection
import Dependencies
import Foundation
import os
import Shared

enum XPCClientError: Error {
    case canNotGetPowerMode
    /// The helper answered with a byte that is not a percentage and did not report an
    /// error. Surfaced rather than clamped: the value's whole purpose is to say which
    /// limit is really in force, and a made-up one would be reported to the user as fact.
    case invalidChargeLimitReply(UInt8)
}

actor XPCClient {
    private lazy var logger = Logger(category: "XPC Client")
    private var _connection: NSXPCConnection?
    /// Identifies the current connection so a dying one cannot clear its replacement. The
    /// watchdog below deliberately tears a connection down and lets the next call build a
    /// new one, which means an old connection's invalidation handler can land after the new
    /// connection is already in place.
    private var connectionID: UUID?

    /// How long a helper call may go unanswered before its connection is torn down.
    ///
    /// Generous on purpose: a false positive is worse than a slow call, because the health
    /// policy answers a failed probe by re-registering the daemon.
    /// `restoreSystemDefaults()` alone can spend ~2s reopening a dropped SMC connection.
    private static let callTimeout = Duration.seconds(15)

    /// The health probe's budget. `ping` does no work at all — a reachable helper answers
    /// it in about 150ms — so this only has to cover a cold daemon spawn, and it is the
    /// probe's speed that decides how long the app can be wrong about itself.
    private static let pingTimeout = Duration.seconds(5)

    private init() { }

    static let shared = XPCClient()

    /// Sends one message to the helper under a watchdog.
    ///
    /// Every call goes through here, because a helper call has no timeout of its own and
    /// can hang for the life of the process. When `SMAppService` reports `.enabled` for a
    /// record whose bundle no longer resolves — the copy of BatFi that registered the
    /// daemon was deleted, moved, or replaced by another copy, which is ordinary once a
    /// user has two or three copies on disk — launchd keeps the mach service registered and
    /// answers the lookup, then fails every spawn with `EX_CONFIG`. The connection is never
    /// invalidated, so `remoteObjectProxyWithErrorHandler` never fires and no reply ever
    /// arrives: the continuation stays suspended forever.
    ///
    /// That one unbounded await starves everything downstream. `ChargingManager` never gets
    /// a charging status, so the app mode stays `.initial` and the menu reads "Initializing"
    /// with no error to explain it; and `HelperHealthPolicy` never gets a ping result, so it
    /// never concludes `.degraded` and never runs the unregister/re-register recovery that
    /// repoints the record at *this* bundle — the one thing that actually fixes it.
    ///
    /// Invalidating is what breaks the deadlock: `NSXPCConnection` calls the error handler
    /// for every message in flight on a connection it invalidates, which resumes the
    /// continuations and turns the hang into a thrown error the policy can act on.
    private func call<T>(
        timeout: Duration = XPCClient.callTimeout,
        _ body: (XPCService, CheckedContinuation<T, Error>) -> Void
    ) async throws -> T {
        let remote = remoteService()
        let watchdog = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.tearDownUnresponsiveConnection(after: timeout)
        }
        defer { watchdog.cancel() }
        return try await remote.withContinuation(body)
    }

    private func tearDownUnresponsiveConnection(after timeout: Duration) {
        guard let connection = _connection else { return }
        logger.error("Helper did not answer within \(timeout.components.seconds, privacy: .public)s; tearing down the connection")
        // Cleared before invalidating so a call that arrives while the handler is in flight
        // builds a fresh connection rather than queueing another message onto a dead one.
        _connection = nil
        connectionID = nil
        connection.invalidate()
    }

    func changeChargingMode(_ newMode: SMCChargingCommand) async throws {
        switch newMode {
        case .forceDischarging:
            try await setChargingMode(XPCService.setForceDischarge)
        case .auto:
            try await setChargingMode(XPCService.setAutocharge)
        case .inhibitCharging:
            try await setChargingMode(XPCService.setInhibitCharge)
        }
    }

    func getPowerDistribution() async throws -> PowerDistributionInfo {
        try await call { service, continuation in
            service.getPowerDistribution { powerInfo, error in
                if let powerInfo {
                    continuation.resume(returning: powerInfo)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both PowerDistributionInfo and error are nil.")
                }
            }
        }
    }

    func restoreSystemDefaults() async throws {
        try await call { (service, continuation: CheckedContinuation<Void, Error>) in
            service.restoreSystemDefaults { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Returns the limit the helper actually put in force, which can be higher than the
    /// one asked for — Apple's Manual Charge Limit cannot go below 80%.
    func applyChargeLimit(_ percentage: Int) async throws -> Int {
        logger.debug("Applying charge limit: \(percentage)")
        return try await call { service, continuation in
            // Clamped rather than trusted: `percentage` reaches here from settings and
            // from automation rules, and a value outside 0...100 would wrap on the way
            // into a byte and ask the helper for a limit nobody chose.
            service.applyChargeLimit(UInt8(clamping: percentage)) { applied, error in
                // Error checked first, unlike the MagSafe pair above. Their sentinel is
                // not a representable option so it fails the value test anyway; a
                // percentage byte has no such luck — UInt8.max would read as a 255%
                // limit if the value arm went first.
                if let error {
                    continuation.resume(throwing: error)
                } else if applied <= 100 {
                    continuation.resume(returning: Int(applied))
                } else {
                    continuation.resume(throwing: XPCClientError.invalidChargeLimitReply(applied))
                }
            }
        }
    }

    func getMCLStatus() async throws -> MCLStatus? {
        try await call { service, continuation in
            service.getMCLStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func getChargingDiagnostics() async throws -> ChargingDiagnostics? {
        try await call { service, continuation in
            service.getChargingDiagnostics { diagnostics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: diagnostics)
                }
            }
        }
    }

    func getSMCChargingStatus() async throws -> SMCChargingStatus {
        try await call { service, continuation in
            service.getCurrentChargingStatus { status, error in
                if let status {
                    continuation.resume(returning: status)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both status and error are nil.")
                }
            }
        }
    }

    func changeMagSafeLEDColor(_ color: MagSafeLEDOption) async throws -> MagSafeLEDOption {
        try await call { service, continuation in
            service.setMagSafeLEDColor(color: color.rawValue) { rawValue, error in
                if let option = MagSafeLEDOption(rawValue: rawValue) {
                    continuation.resume(returning: option)
                } else if let error {
                    self.logger.error("Error when setting MagSafe LED color: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both option and error are nil.")
                }
            }
        }
    }

    func currentMagSafeLEDOption() async throws -> MagSafeLEDOption {
        try await call { service, continuation in
            service.getMagSafeLEDOption { rawValue, error in
                if let option = MagSafeLEDOption(rawValue: rawValue) {
                    continuation.resume(returning: option)
                } else if let error {
                    self.logger.error("Error when getting MagSafe LED color: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both option and error are nil.")
                }
            }
        }
    }

    func pingHelper() async throws -> Bool {
        logger.debug("Pinging helper")
        // The probe that decides whether the app believes in its helper at all, so it gets
        // the short budget rather than the working-call one.
        return try await call(timeout: Self.pingTimeout) { service, continuation in
            service.ping { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// The process identifier of the helper currently on the other end.
    ///
    /// `NSXPCConnection` only learns the peer's pid once a message has crossed, so this
    /// pings first when the number is not yet there — otherwise the very first identity
    /// check after launch would read 0 and report no verdict, which is the case it most
    /// needs to answer.
    func helperProcessIdentifier() async throws -> pid_t {
        let existing = connection().processIdentifier
        if existing > 0 { return existing }
        _ = try await pingHelper()
        return connection().processIdentifier
    }

    func quitHelper() async throws -> Bool {
        logger.debug("Quitting helper")
        return try await call(timeout: Self.pingTimeout) { service, continuation in
            service.quit { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setPowerMode(_ mode: UInt8, lowPowerModeOnly: Bool) async throws {
        logger.debug("Setting power mode: \(mode)")
        return try await call { service, continuation in
            service.turnPowerMode(mode, lowPowerModeOnly: lowPowerModeOnly) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func getPowerMode() async throws -> (UInt8, Bool) {
        logger.debug("Getting power mode")
        return try await call { service, continuation in
            service.currentPowerMode { mode, highPowerModeIsAvailable in
                if let uint = mode?.uint8Value {
                    continuation.resume(returning: (uint, highPowerModeIsAvailable))
                } else {
                    continuation.resume(throwing: XPCClientError.canNotGetPowerMode)
                }
            }
        }
    }

    func setDisableAutosleep(_ disable: Bool) async throws {
        logger.debug("Setting disable autosleep: \(disable)")
        return try await call { service, continuation in
            service.disableAutosleep(disable, { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }


    // MARK: - Private

    private func setChargingMode(
        _ handler: (XPCService) -> (@escaping (Error?) -> Void) -> Void
    ) async throws {
        try await call { (service, continuation: CheckedContinuation<Void, Error>) in
            handler(service)() { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func remoteService() -> RemoteXPCService<XPCService> {
        RemoteXPCService(connection: connection())
    }

    private func connection() -> NSXPCConnection {
        if let existing = _connection {
            return existing
        }
        let connection = NSXPCConnection(
            machServiceName: Constant.helperBundleIdentifier,
            options: .privileged
        )
        connection.setCodeSigningRequirement(xpcEntitlement)
        connection.remoteObjectInterface = NSXPCInterface(with: XPCService.self)
        let id = UUID()
        // The handlers, not the tasks they spawn, are what the connection holds on to, so the
        // weak capture belongs on them. Spelled on the inner `Task` it bought nothing: the
        // outer closure still captured `self` strongly to have something to weaken.
        connection.invalidationHandler = { [weak self] in
            Task { await self?.connectionDidInvalidate(id) }
        }
        connection.interruptionHandler = { [weak self] in
            Task { await self?.connectionDidInvalidate(id) }
        }
        connection.resume()
        _connection = connection
        connectionID = id
        return connection
    }

    /// - Parameter id: which connection died. The watchdog tears a connection down and lets
    ///   the next call build a replacement immediately, so a late handler from the old
    ///   connection must not clear — or report the death of — the one now in use.
    private func connectionDidInvalidate(_ id: UUID) {
        guard connectionID == id else { return }
        connectionID = nil
        _connection = nil
        // A fact for the health policy, not a verdict. Connections also die for reasons
        // that have nothing to do with a wedged helper, so this only prompts a ping —
        // nothing mutating happens until that ping fails twice.
        NotificationCenter.default.post(name: HelperConnectionDidFailNotificationName, object: nil)
    }
}
