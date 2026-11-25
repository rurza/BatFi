//
//  OtherChargeToolsClient.swift
//  BatFi
//
//  Finds other charge-control tools installed on this Mac. See `OtherChargeToolDetection`
//  for what counts as installed.
//

import Dependencies
import DependenciesMacros
import Shared

/// Scans for other charge-control tools and remembers the last answer.
///
/// `detect()` scans and is the only thing that does; `latest()` and `observe()` read what
/// the last scan found, so a consumer that wants to name a tool — the charge-hold drift
/// warning, a menu row — never pays for a scan or races one. The app scans once at launch;
/// Settings rescans when the Charging pane opens, with
/// `Task { await otherChargeTools.detect() }`.
///
/// The scan is cheap — a couple of dozen `stat`s and a few Launch Services lookups — and
/// runs off the main actor.
@DependencyClient
public struct OtherChargeToolsClient: Sendable {
    /// Scans now, stores the result for `latest()` and `observe()`, and returns it.
    public var detect: @Sendable () async -> [DetectedChargeTool] = { [] }
    /// What the last scan found, or nil before the first scan has finished.
    public var latest: @Sendable () async -> [DetectedChargeTool]? = { nil }
    /// The last scan's result now, if there is one, then every later scan's.
    public var observe: @Sendable () -> AsyncStream<[DetectedChargeTool]> = { AsyncStream { _ in } }
}

extension OtherChargeToolsClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: OtherChargeToolsClient = .init()
}

public extension DependencyValues {
    var otherChargeTools: OtherChargeToolsClient {
        get { self[OtherChargeToolsClient.self] }
        set { self[OtherChargeToolsClient.self] = newValue }
    }
}
