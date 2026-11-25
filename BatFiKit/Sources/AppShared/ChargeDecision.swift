//
//  ChargeDecision.swift
//
//
//  What `ChargingManager.updateStatus` does when no override is in force: charge, hold, or
//  run BatFi's own discharge. Moved out of `ChargingManager` as it stood, so it can be tested
//  on its own; `AppCore` has no test target.
//
//  The asynchronous questions the old chain asked inline — whether macOS drains to the limit
//  itself, whether the backend can pause on demand, whether macOS or the firmware band is
//  holding charge — are answered by the caller and arrive here as inputs.
//

import Foundation

/// The mode one pass of the charging loop settles on, with no override in force.
public enum ChargeDecision: Equatable, Sendable {
    /// BatFi's own discharge, on a battery above the limit.
    case discharge
    /// At or above the limit and not discharging: charge is held.
    case inhibitAtLimit
    /// Below the limit, held because charging pauses while the Mac sleeps.
    case inhibitForSleep
    /// Below the limit, held while sailing drifts down to its resume level.
    case inhibitForSailing
    /// Below the limit, held by macOS under its own charge limit.
    case inhibitBySystemHold
    /// Below the limit, held by the firmware inside its charge band.
    case inhibitByFirmwareRange
    case charge
}

public struct ChargeDecisionInputs: Equatable, Sendable {
    public var batteryLevel: Int
    /// The limit actually in force, not the one requested.
    public var limitInForce: Int
    public var allowDischarging: Bool
    public var lidOpenOrSleepDisabled: Bool
    public var computerIsAsleep: Bool
    /// The charge mechanism drains to the limit in force by itself (Apple's charge limit).
    public var systemDischargesToLimitItself: Bool
    /// Pause-charging-on-sleep is on, the Mac is asleep, and the backend can pause on demand.
    public var pausesChargingForSleep: Bool
    public var systemIsHoldingBelowLimit: Bool
    public var firmwareRangeIsHolding: Bool
    /// Sailing's phase this pass; nil when sailing is not in play.
    public var sailingPhase: SailingPhase?

    public init(
        batteryLevel: Int,
        limitInForce: Int,
        allowDischarging: Bool,
        lidOpenOrSleepDisabled: Bool,
        computerIsAsleep: Bool,
        systemDischargesToLimitItself: Bool,
        pausesChargingForSleep: Bool,
        systemIsHoldingBelowLimit: Bool,
        firmwareRangeIsHolding: Bool,
        sailingPhase: SailingPhase? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.limitInForce = limitInForce
        self.allowDischarging = allowDischarging
        self.lidOpenOrSleepDisabled = lidOpenOrSleepDisabled
        self.computerIsAsleep = computerIsAsleep
        self.systemDischargesToLimitItself = systemDischargesToLimitItself
        self.pausesChargingForSleep = pausesChargingForSleep
        self.systemIsHoldingBelowLimit = systemIsHoldingBelowLimit
        self.firmwareRangeIsHolding = firmwareRangeIsHolding
        self.sailingPhase = sailingPhase
    }
}

public enum ChargeDecisionRule {
    /// The no-override arm of `ChargingManager.updateStatus`, as it stands today.
    ///
    /// At or above the limit in force:
    /// - BatFi discharges only above it, with discharging allowed, the lid open or sleep
    ///   disabled, the Mac awake, and a mechanism that does not drain to the limit itself.
    ///   Under Apple's charge limit macOS performs that drain, to exactly the limit in force;
    ///   running `CHIE` alongside it would duplicate a discharge already happening and take a
    ///   sleep assertion that buys nothing, since the system's drain continues asleep.
    /// - Otherwise charge is held. `.inhibit` is the honest mode even where macOS is the one
    ///   holding (and draining): the same condition the discharge steps aside for, so the two
    ///   can never both claim the battery is being discharged.
    ///
    /// Below it, in this order:
    /// - Paused for sleep, where the backend can pause on demand — above the system hold so an
    ///   inhibit BatFi genuinely asked for keeps its own label.
    /// - Sailing holding while the battery drifts to its resume level — BatFi's own hold, so
    ///   it outranks the holds macOS or the firmware would otherwise be credited with.
    /// - macOS holding charge under its own limit. Charging would write nothing there and
    ///   report `.charging` for a battery taking 0 mA, so the hold is reported as `.inhibit`.
    /// - The firmware band holding while the battery drifts to its lower bound, likewise
    ///   `.inhibit`, so neither the menu nor the MagSafe light says "charging" over it.
    /// - Otherwise charge.
    public static func decide(_ inputs: ChargeDecisionInputs) -> ChargeDecision {
        if inputs.batteryLevel >= inputs.limitInForce {
            if inputs.batteryLevel > inputs.limitInForce, inputs.allowDischarging,
               inputs.lidOpenOrSleepDisabled, !inputs.computerIsAsleep,
               !inputs.systemDischargesToLimitItself {
                return .discharge
            }
            return .inhibitAtLimit
        }
        if inputs.pausesChargingForSleep { return .inhibitForSleep }
        if inputs.sailingPhase == .holding { return .inhibitForSailing }
        if inputs.systemIsHoldingBelowLimit { return .inhibitBySystemHold }
        if inputs.firmwareRangeIsHolding { return .inhibitByFirmwareRange }
        return .charge
    }
}

public extension ChargeDecisionRule {
    /// The override arm's charge-or-hold choice (its discharge test stays in the manager).
    ///
    /// At or above the limit in force charge is held; below it sailing's hold applies when it
    /// is holding, and otherwise the battery charges.
    static func chargeOrHold(batteryLevel: Int, limitInForce: Int, sailingPhase: SailingPhase?) -> ChargeDecision {
        if batteryLevel >= limitInForce { return .inhibitAtLimit }
        if sailingPhase == .holding { return .inhibitForSailing }
        return .charge
    }
}
