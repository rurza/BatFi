//
//  OnBatterySettle.swift
//  BatFi
//
//  How long the Mac has to have been on its battery before "Slow down on battery" slows
//  anything down.
//

import Foundation

/// Keeps track of whether the Mac has been on its battery long enough to slow apps down.
///
/// On firmware that no longer publishes `ExternalConnected`, whether the charger is in is
/// read from IOKit's power-source string, and IOKit lags the SMC. So the start or the end of
/// BatFi's own force discharge can read as battery power for a moment while the charger is
/// in, and the apps the user slows down would be slowed for it. Slowing waits until the Mac
/// has been on its battery for `duration`.
///
/// The two directions are handled differently on purpose, as `FrontmostGrace`'s are: giving
/// back on the charger never waits. A moment of "on the charger" that is not real costs a
/// give-back and a slowdown again; a moment of "on battery" that is not real would slow an
/// app on the charger.
///
/// Each stretch on battery carries a generation, so that the timer of one the charger has
/// since ended settles nothing.
public struct OnBatterySettle: Equatable, Sendable {
    /// How long the Mac has to have been on its battery.
    public static let duration: Duration = .seconds(2)

    /// One stretch on battery, as its timer has to hand it back when it runs out.
    public struct Wait: Hashable, Sendable {
        public let generation: UInt64
    }

    /// Whether the Mac has been on its battery for `duration`, and is still.
    public private(set) var isSettled = false
    private var isOnBattery = false
    private var generation: UInt64 = 0

    public init() {}

    /// Records whether the Mac is on its battery now.
    ///
    /// - Returns: the wait to run out, where a stretch on battery has just begun.
    public mutating func powerChanged(onBattery: Bool) -> Wait? {
        guard onBattery != isOnBattery else { return nil }
        isOnBattery = onBattery
        isSettled = false
        generation += 1
        return onBattery ? Wait(generation: generation) : nil
    }

    /// Waits out a stretch on battery on `clock`.
    ///
    /// - Returns: whether it ran out; false if the waiting task was cancelled first.
    public static func runOut(on clock: any Clock<Duration>) async -> Bool {
        (try? await clock.sleep(for: duration)) != nil
    }

    /// Ends a wait whose timer ran out.
    ///
    /// - Returns: whether the Mac has only now settled on its battery, in which case apps may
    ///   be slowed down and a pass is worth running.
    public mutating func waitRanOut(_ wait: Wait) -> Bool {
        guard wait.generation == generation, isOnBattery, !isSettled else { return false }
        isSettled = true
        return true
    }
}
