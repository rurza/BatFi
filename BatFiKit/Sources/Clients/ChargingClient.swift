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
    /// `applyChargeLimit` with a resume level: where the firmware holds a band, the band
    /// reaches down to `resumeLevel` rather than a few points under the limit. Returns the
    /// limit actually in force, as `applyChargeLimit` does, and which call went out.
    ///
    /// Against a helper too old to know this, one whose version cannot be read, or one that
    /// refused this range, falls back to `applyChargeLimit(limit)`, so the limit is applied
    /// either way — and reports `.limitOnly`, because the firmware then keeps today's band.
    public var applyChargeRange: @Sendable (_ limit: Int, _ resumeLevel: Int) async throws -> AppliedChargeRange
    /// Whether `applyChargeRange(limit, resumeLevel)` would go out as the two-value call —
    /// the running helper knows it and has not refused this exact range — asked ahead and
    /// changing nothing. Sailing under `.firmwareRange` enforces its hold only where it would.
    public var chargeRangeCallIsAvailable: @Sendable (_ limit: Int, _ resumeLevel: Int) async -> Bool = { _, _ in false }
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
