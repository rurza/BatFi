//
//  PowerModeClient.swift
//  BatFiKit
//
//  Created by Adam Różyński on 20.11.2024.
//

import Dependencies
import Foundation
import Shared

public enum PowerMode: Sendable {
    case low, normal, high
}

public enum PowerModeClientError: Error {
    case unsupportedMode
}

public struct PowerModeClient: TestDependencyKey, Sendable {
    public var getCurrentPowerMode: @Sendable () async throws -> (PowerMode, Bool)
    public var setPowerMode: @Sendable (PowerMode, _ lowPowerModeOnly: Bool) async throws -> Void
    public var observePowerMode: @Sendable () -> AsyncStream<PowerMode>
    /// Low Power Mode for each power source, or `nil` where it could not be read —
    /// including from a helper too old to be asked.
    public var powerModeBySource: @Sendable () async -> PowerModeBySource?
    /// Sets Low Power Mode for the battery profile only, under the key it was read from,
    /// leaving the AC profile as the user chose it.
    public var setBatteryPowerMode: @Sendable (_ value: UInt8, _ usesPowermodeKey: Bool) async throws -> Void
    /// Hands the helper the record to restore if it exits while BatFi still holds Low Power
    /// Mode on the battery; `nil` disarms it.
    public var armPowerModeRestoreOnExit: @Sendable (AutoLowPowerModeRecord?) async throws -> Void
    /// Whether Low Power Mode is in effect right now, current value first, then on every
    /// change — whoever makes it.
    public var lowPowerModeActiveChanges: @Sendable () -> AsyncStream<Bool>

    public init(
        getCurrentPowerMode: @escaping @Sendable () async throws -> (PowerMode, Bool),
        setPowerMode: @escaping @Sendable (PowerMode, Bool) async throws -> Void,
        observePowerMode: @escaping @Sendable () -> AsyncStream<PowerMode>,
        powerModeBySource: @escaping @Sendable () async -> PowerModeBySource? = { nil },
        setBatteryPowerMode: @escaping @Sendable (UInt8, Bool) async throws -> Void = { _, _ in },
        armPowerModeRestoreOnExit: @escaping @Sendable (AutoLowPowerModeRecord?) async throws -> Void = { _ in },
        lowPowerModeActiveChanges: @escaping @Sendable () -> AsyncStream<Bool> = { AsyncStream { $0.finish() } }
    ) {
        self.getCurrentPowerMode = getCurrentPowerMode
        self.setPowerMode = setPowerMode
        self.observePowerMode = observePowerMode
        self.powerModeBySource = powerModeBySource
        self.setBatteryPowerMode = setBatteryPowerMode
        self.armPowerModeRestoreOnExit = armPowerModeRestoreOnExit
        self.lowPowerModeActiveChanges = lowPowerModeActiveChanges
    }

    nonisolated(unsafe) public static var testValue: PowerModeClient = unimplemented()
}

extension DependencyValues {
    public var powerModeClient: PowerModeClient {
        get { self[PowerModeClient.self] }
        set { self[PowerModeClient.self] = newValue }
    }
}

public extension Notification.Name {
    /// Posted by the live client after each Low Power Mode write that succeeded — BatFi's
    /// own manual toggle and hotkeys as well as the automatic battery-only write — with the
    /// mode now in use as `userInfo["powerMode"]` (`UInt8`). The battery icon listens for
    /// it, and so does the automatic Low Power Mode, so that it notices at once when the
    /// setting it holds is changed under it.
    static let powerModeDidChange = Notification.Name("BatFiKit.PowerModeClient.PowerModeDidChange")
}
