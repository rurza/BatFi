//
//  SailingPhase.swift
//  BatFi
//
//  Sailing either charges up to the limit or holds while the battery drifts down to the resume
//  level. Which one is a matter of history — at 75% between 70 and 80 it could be either — so
//  the phase is carried from pass to pass, and forgotten whenever that history stops meaning
//  anything: the charger coming out, sailing leaving play, or an override ending. A temporary
//  limit arming or changing is only a level change, so the phase carries through it.
//

import Foundation

/// Where sailing is in its cycle.
public enum SailingPhase: Equatable, Sendable {
    /// Charging up to the limit.
    case charging
    /// Not charging while the battery drifts down to the resume level.
    case holding
}

public enum SailingPhaseRule {
    /// The phase for this pass.
    ///
    /// Holding runs down to exactly the resume level; charging starts strictly below it, and
    /// stops only at the limit. A fresh start holds at or above the resume level and charges
    /// below it.
    ///
    /// nil `previous` = a fresh start (connection, launch, sailing turned on, wake, override ended).
    /// A kept `previous` against new levels (a rule's limit or a temporary limit) stays unless the
    /// new levels contradict it.
    public static func next(after previous: SailingPhase?, batteryLevel: Int, levels: SailingLevels) -> SailingPhase {
        switch previous {
        case nil:
            batteryLevel >= levels.resumeLevel ? .holding : .charging
        case .charging:
            batteryLevel >= levels.limit ? .holding : .charging
        case .holding:
            batteryLevel < levels.resumeLevel ? .charging : .holding
        }
    }
}

/// The phase carried between passes of the charging loop.
public struct SailingPhaseTracker: Equatable, Sendable {
    public private(set) var phase: SailingPhase?
    /// Whether the last `advance` started the phase anew — from no phase, or after an override
    /// ended — rather than carrying it from the pass before. Where the firmware holds a band, a
    /// hold that starts afresh is re-established at the current charge (`FirmwareSailingHold`).
    public private(set) var startedAfresh = false
    /// The override in force on the previous pass, so its ending can be noticed.
    private var previousOverride: UserTempChargingMode?

    public init() {}

    /// Advances once per pass. Forgets on: charger not connected (the resolved value), levels nil
    /// (a pause, Charge to 100% and its hold, sailing off), or an override ending — in force on the
    /// previous pass, none on this one. A temporary limit arming or changing keeps the phase: it is
    /// a level change, as a rule's limit changing is.
    ///
    /// `chargerConnected` is the resolved connection, so BatFi's own discharge — which reads as
    /// battery power on derived firmware — does not count as unplugging.
    public mutating func advance(
        chargerConnected: Bool,
        levels: SailingLevels?,
        overrideInForce: UserTempChargingMode?,
        batteryLevel: Int
    ) -> SailingPhase? {
        let overrideEnded = previousOverride != nil && overrideInForce == nil
        previousOverride = overrideInForce
        guard chargerConnected, let levels else {
            phase = nil
            startedAfresh = false
            return nil
        }
        let previous = overrideEnded ? nil : phase
        startedAfresh = previous == nil
        phase = SailingPhaseRule.next(after: previous, batteryLevel: batteryLevel, levels: levels)
        return phase
    }

    /// Charge to the limit first, then sail (the fallback for a hold that cannot be expressed).
    /// Call it after `advance`: a fresh start on the same pass would discard it.
    public mutating func chargeToLimitFirst() {
        phase = .charging
    }

    /// Wake, licence hand-back, management switched off.
    public mutating func forget() {
        phase = nil
        startedAfresh = false
    }
}
