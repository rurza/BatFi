//
//  ChargeRangeText.swift
//  BatFi
//
//  A rule's charge levels as printed in the rule list, the "rule active" banner and the rule
//  editor: "70–80%" for a rule that sails, "80%" otherwise. The range is written in the style
//  of the single percentage the same place prints, so it needs no string of its own to
//  translate and never looks different from the plain rule beside it.
//

import Foundation

public enum ChargeRangeText {
    /// The rule's levels, its stored resume level corrected against its limit first.
    public static func text(
        for rule: AutomationRule,
        percentage: (Int) -> String = hardCodedPercentage
    ) -> String {
        text(limit: rule.limit, resumeLevel: rule.sailingLevels?.resumeLevel, percentage: percentage)
    }

    /// `percentage(limit)` without a resume level. With one, that same text with the limit's
    /// number replaced by "resume–limit", so the sign sits where that place puts it for a
    /// single value: "70–80%", "70–80 %", "%70–80".
    ///
    /// - Parameter percentage: how this place prints a single percentage — a translated
    ///   fragment where it has one, else the hard-coded "80%".
    public static func text(
        limit: Int,
        resumeLevel: Int?,
        percentage: (Int) -> String = hardCodedPercentage
    ) -> String {
        let single = percentage(limit)
        guard let resumeLevel else { return single }
        let range = "\(resumeLevel)–\(limit)"
        guard let number = single.range(of: String(limit)) else { return "\(resumeLevel)–\(single)" }
        return single.replacingCharacters(in: number, with: range)
    }

    /// "80%": how the rule editor has always printed a level.
    public static func hardCodedPercentage(_ value: Int) -> String {
        "\(value)%"
    }
}
