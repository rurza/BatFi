//
//  SailingRange.swift
//  BatFi
//
//  Sailing lets the battery drift down from the limit to a lower resume level before charging
//  again. This is where the two levels come from: the resume level the person chose, the one a
//  temporary limit derives from it, a rule's own, whether sailing is in play at all this pass,
//  and how the two slider handles push and stop each other.
//

import Foundation

/// The pair sailing works between: hold at `limit`, charge again only below `resumeLevel`.
public struct SailingLevels: Equatable, Sendable {
    public let limit: Int
    public let resumeLevel: Int

    public init(limit: Int, resumeLevel: Int) {
        self.limit = limit
        self.resumeLevel = resumeLevel
    }
}

public enum SailingRange {
    /// The lowest resume level offered or derived.
    public static let floor = 20
    /// The resume handle moves in the same steps as the limit handle.
    public static let step = 5
    /// The resume level always sits at least this far below the limit.
    public static let minimumGap = 5
    /// Where the resume level starts before the person has ever chosen one.
    public static let firstTimeDistance = 10

    /// The resume level the slider shows and a temporary limit derives from: stored ?? limit − 10, clamped to floor...limit − 5.
    ///
    /// The stored value is clamped rather than trusted because the limit can move without the
    /// resume handle being dragged — a stale value above the limit must still read as a gap.
    public static func resolvedResumeLevel(limit: Int, stored: Int?) -> Int {
        let wanted = stored ?? limit - firstTimeDistance
        return max(floor, min(wanted, limit - minimumGap))
    }

    /// Whether a limit leaves room for a resume level: at least 5 above the floor, so 25 or more.
    public static func canSail(limit: Int) -> Bool {
        limit - floor >= minimumGap
    }

    /// A rule's own resume level, corrected against `limit`: snapped to the nearest step, then
    /// kept between the floor and 5 below the limit. nil when the rule does not sail — no level
    /// stored, or a limit below 25, which leaves no 5-point gap above the floor.
    ///
    /// Corrected rather than trusted for the same reason as `resolvedResumeLevel`: the rule's
    /// limit can be lowered under a level chosen earlier, and the pair must never invert.
    public static func ruleResumeLevel(limit: Int, stored: Int?) -> Int? {
        guard let stored, canSail(limit: limit) else { return nil }
        let snapped = Int((Double(stored) / Double(step)).rounded()) * step
        return resolvedResumeLevel(limit: limit, stored: snapped)
    }

    /// Same distance below `limit` as the configured pair; nil when the floor leaves no 5-point gap.
    ///
    /// `configuredLimit` is the limit as the slider displays it, so the distance kept is the one
    /// the person sees.
    public static func resumeLevel(forLimit limit: Int, configuredLimit: Int, configuredResume: Int?) -> Int? {
        let distance = configuredLimit - resolvedResumeLevel(limit: configuredLimit, stored: configuredResume)
        let resume = max(floor, limit - distance)
        return limit - resume >= minimumGap ? resume : nil
    }

    /// Whether the settings that count this pass have sailing on. They follow the limit's
    /// source: a temporary limit (which beats a rule) goes by the main screen's switch; an active
    /// rule only by its own resume level, whatever the main switch says; with neither, the main
    /// screen's switch.
    public static func switchIsOn(
        mainSwitch: Bool,
        automation: AutomationTarget?,
        overrideInForce: UserTempChargingMode?
    ) -> Bool {
        if overrideInForce != nil { return mainSwitch }
        if let automation { return automation.resumeLevel != nil }
        return mainSwitch
    }

    /// The levels sailing works against this pass, or nil when sailing is not in play.
    ///
    /// `enabled` is the main screen's switch and `configuredLimit`/`configuredResume` its pair.
    /// `targetLimit` is the limit this pass requests, which already follows the precedence
    /// temporary limit > rule > main screen; the sailing settings follow the same source:
    /// - a temporary limit sails at the main screen's distance below it, by the main switch;
    /// - an active rule sails only by its own resume level (`ruleResumeLevel`, corrected
    ///   against `targetLimit`), whatever the main switch says;
    /// - otherwise the main screen's pair applies.
    ///
    /// Charge to 100% (the request and the hold that follows it) and a manual pause both take
    /// priority over sailing, as does a backend that cannot sail (`backendCanSail`).
    public static func levelsInPlay(
        enabled: Bool,
        backendCanSail: Bool = true,
        targetLimit: Int,
        configuredLimit: Int,
        configuredResume: Int?,
        automation: AutomationTarget? = nil,
        overrideInForce: UserTempChargingMode?,
        holdingFullChargeUntilUnplugged: Bool
    ) -> SailingLevels? {
        guard backendCanSail, !holdingFullChargeUntilUnplugged else { return nil }
        guard switchIsOn(mainSwitch: enabled, automation: automation, overrideInForce: overrideInForce) else {
            return nil
        }
        if let overrideInForce, overrideInForce.isInhibit || overrideInForce.limit >= 100 {
            return nil
        }
        let resume: Int?
        if overrideInForce == nil, let automation {
            resume = ruleResumeLevel(limit: targetLimit, stored: automation.resumeLevel)
        } else {
            resume = resumeLevel(forLimit: targetLimit, configuredLimit: configuredLimit, configuredResume: configuredResume)
        }
        return resume.map { SailingLevels(limit: targetLimit, resumeLevel: $0) }
    }

    /// Dragging the limit handle: the resume handle is pushed ahead to stay 5 below.
    public static func draggingLimit(to limit: Int, resume: Int) -> SailingLevels {
        SailingLevels(limit: limit, resumeLevel: resolvedResumeLevel(limit: limit, stored: resume))
    }

    /// Dragging the resume handle: stops 5 short of the limit and at the floor.
    public static func draggingResume(to resume: Int, limit: Int) -> Int {
        resolvedResumeLevel(limit: limit, stored: resume)
    }

    /// Lower end of the slider track: 20 while sailing is on, else the limit's own floor.
    public static func trackLowerBound(sailingEnabled: Bool, lowestLimit: Int) -> Int {
        sailingEnabled ? floor : lowestLimit
    }
}
