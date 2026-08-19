//
//  ChargingClient.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Dependencies
import DependenciesMacros
import Shared

@DependencyClient
public struct ChargingClient: Sendable {
    public var turnOnAutoChargingMode: @Sendable () async throws -> Void
    public var inhibitCharging: @Sendable () async throws -> Void
    public var forceDischarge: @Sendable () async throws -> Void
    public var restoreSystemDefaults: @Sendable () async throws -> Void
    /// Puts a charge limit in force and returns the one actually applied. Not always the
    /// value passed in: where Apple's Manual Charge Limit is the only mechanism it cannot
    /// go below 80%, so a lower request comes back raised. Under the SMC backends the
    /// limit is expressed as an inhibit and the request is honoured exactly, so they
    /// return it unchanged.
    public var applyChargeLimit: @Sendable (_ percentage: Int) async throws -> Int
    /// Applies a limit with the helper's record of what it already applied thrown away, and
    /// returns the one actually put in force.
    ///
    /// For the case `applyChargeLimit` cannot serve: it skips the write when the limit it
    /// recorded matches the request, which is right on the pass where nothing has changed
    /// and wrong on the pass where the battery says the recorded limit is not holding.
    public var reassertChargeLimit: @Sendable (_ percentage: Int) async throws -> Int
    /// Moves the enforced limit to `nudgeValue` and restores `target`, to re-open a charge
    /// session macOS closed while the battery sits below the limit. Returns whether a nudge was
    /// actually performed — false where the backend cannot be in that state.
    public var nudgeChargeLimit: @Sendable (_ nudgeValue: Int, _ target: Int) async throws -> Bool
    public var chargingStatus: @Sendable () async throws -> SMCChargingStatus
    public var mclStatus: @Sendable () async throws -> MCLStatus?
    public var chargingDiagnostics: @Sendable () async throws -> ChargingDiagnostics?
}

extension ChargingClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: ChargingClient = .init()
}

public extension DependencyValues {
    var chargingClient: ChargingClient {
        get { self[ChargingClient.self] }
        set { self[ChargingClient.self] = newValue }
    }
}
