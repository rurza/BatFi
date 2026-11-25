//
//  AppChargingMode.swift
//
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public struct AppChargingMode: Equatable, Identifiable, CustomStringConvertible, Sendable {
    public let mode: ChargingMode
    public let userTempOverride: UserTempChargingMode?
    public let chargerConnected: Bool

    /// Whether macOS is draining the battery down to the limit right now, on its own.
    ///
    /// Not a fourth `ChargingMode`. `ChargingMode` is what BatFi last *told the hardware*,
    /// and this is the opposite: a state BatFi did not ask for and cannot stop — the
    /// `drain: true` in the `ChargeCtrlPolicy` behind Apple's Manual Charge Limit, which is
    /// exposed only behind an Apple-private entitlement. Making it a mode would put it in
    /// front of `shouldApply` and the appliers, which decide what to write, and there is no
    /// write.
    ///
    /// It exists because `.inhibit` is the honest mode for "charge is being held, just not
    /// by me" and the honest *label* for it is a different sentence. A user watching 61%
    /// fall toward a 55% limit while the menu reads "Inhibiting charging" is being told
    /// something they can see is false, and the mechanism that makes it false is the same
    /// one `ChargeBackend.dischargesToLimitItself` names.
    ///
    /// **Defaults to `false`, which means "not known to be draining" rather than "holding
    /// steady".** Every construction site that has not worked the answer out — the initial
    /// state, the helper's status read, a charger-connection update — leaves it alone, and
    /// `ChargingManager` is the one place that knows the battery level, the limit actually
    /// in force and the backend at the same moment. Erring this way costs the old label on
    /// a Mac that is draining; erring the other way would claim a drain on every Mac that
    /// is not.
    public let systemIsDischargingToLimit: Bool

    /// Whether macOS is holding charge on a battery that sits **below** the limit.
    ///
    /// The other half of what `.inhibit` covers on a mechanism that owns the charging
    /// decision, and it is here for the same reasons `systemIsDischargingToLimit` is: BatFi
    /// did not ask for it, issues no write while it lasts, and cannot currently end it —
    /// re-writing the same limit does not re-open the charge session macOS closed.
    ///
    /// Mutually exclusive with the drain in practice, because that one needs the battery
    /// above the limit and this one needs it below. The struct cannot express that; the
    /// precedence lives in `stateDescription` and is pinned by a test.
    ///
    /// **Defaults to `false`, meaning "not known to be held"** — the same reading the drain
    /// flag gets. `ChargingManager` is the one place that knows the level, the limit in
    /// force, the firmware's attribution and the backend at the same moment.
    public let systemIsHoldingBelowLimit: Bool

    /// Whether macOS is charging the battery **past** the limit, on its own.
    ///
    /// The third thing `.inhibit` covers on a mechanism that owns the charging decision, and
    /// here for the same reasons the other two are: Apple's charge limit occasionally charges
    /// to 100% to keep its state-of-charge estimate honest, BatFi's limit stays in force
    /// throughout, and BatFi issues no write and cannot stop it. See `SystemChargeTopUp`.
    ///
    /// Mutually exclusive with the drain by construction rather than in practice — the two
    /// read one direction rule and negate it — and with the hold, which needs the battery
    /// below the limit. The struct still cannot express that; the precedence lives in
    /// `stateDescription` and is pinned by a test.
    ///
    /// **Defaults to `false`, meaning "not known to be charging past the limit"** — the same
    /// reading the other two flags get, and erring the same way: it costs the plain inhibit
    /// label on a Mac being topped up, where claiming a top-up by default would put "macOS is
    /// calibrating the battery" on every Mac holding its limit correctly.
    public let systemIsChargingPastLimit: Bool

    /// Whether BatFi is keeping the battery at 100% until the charger is unplugged, because
    /// the user asked it to charge to full and it got there.
    ///
    /// Unlike the three flags above, this is **BatFi's own chosen state, not a system one**.
    /// The others exist because `.inhibit` was being credited to BatFi when macOS was doing
    /// the holding; this one exists because the hold has no single mode at all. BatFi keeps
    /// requesting a limit of 100 (see `ChargeToFullHold`), so the mode underneath alternates:
    /// `.charging` while a battery that slipped to 99% is topped back up, `.inhibit` while it
    /// rests at 100. Both are one state to the user, and a label that flickered between
    /// "Charging to the limit" and "Inhibiting charging" would describe a fault rather than a
    /// request being honoured.
    ///
    /// **Defaults to `false`, meaning "not holding".** `ChargingManager` is the only thing
    /// that knows a charge-to-full override completed, and the flag lives there rather than
    /// on the override because the override is gone by the time the hold begins.
    public let isHoldingFullChargeUntilUnplugged: Bool

    /// Whether `chargerConnected` was published ahead of a mode worked out for it, so `mode`
    /// and the flags above still describe the charger state before the change.
    ///
    /// On a plug-in `ChargingManager` applies the charge limit before any applier runs, and
    /// on macOS 27 with a sub-80% limit that apply waits up to 45 s for powerd to adopt it.
    /// The connection is published first so the icon follows the charger at once; the mode
    /// follows when the applier publishes it, which clears this. Until then the mode is not
    /// news: rendered with the charger connected, the on-battery mode names a state BatFi has
    /// not chosen — and announcing it can make the right banner a quiet sub-state change
    /// that is never posted. `ModeChangeAnnouncement.consideration` waits on it.
    ///
    /// **Defaults to `false`.** Only `withChargerConnected(_:awaitingMode:)` sets it.
    public let isAwaitingModeForChargerChange: Bool

    /// The level below which charging resumes, while sailing is holding charge — nil
    /// otherwise.
    ///
    /// Like `isHoldingFullChargeUntilUnplugged`, BatFi's own chosen state: the battery sits
    /// below the limit under `.inhibit`, and the label has to say why and until when rather
    /// than "Inhibiting charging". Read only under `.inhibit`; see `stateDescription` for
    /// where it ranks among the system states.
    ///
    /// **Defaults to nil, meaning "not holding for sailing".** `ChargingManager` publishes it
    /// through `AppChargingStateClient.setSailingHold` in the pass that holds.
    public let sailingResumeLevel: Int?

    public var id: String {
        "\(mode.id)\(userTempOverride?.id.description ?? "null")\(chargerConnected)\(systemIsDischargingToLimit)\(systemIsHoldingBelowLimit)\(systemIsChargingPastLimit)\(isHoldingFullChargeUntilUnplugged)\(isAwaitingModeForChargerChange)\(sailingResumeLevel?.description ?? "null")"
    }

    public var description: String {
        """
        mode: \(mode.rawValue)
        userTempOverride: \(userTempOverride?.limit.description ?? "nil")
        chargerConnected: \(chargerConnected)
        systemIsDischargingToLimit: \(systemIsDischargingToLimit)
        systemIsHoldingBelowLimit: \(systemIsHoldingBelowLimit)
        systemIsChargingPastLimit: \(systemIsChargingPastLimit)
        isHoldingFullChargeUntilUnplugged: \(isHoldingFullChargeUntilUnplugged)
        isAwaitingModeForChargerChange: \(isAwaitingModeForChargerChange)
        sailingResumeLevel: \(sailingResumeLevel?.description ?? "nil")
        """
    }

    public init(
        mode: ChargingMode,
        userTempOverride: UserTempChargingMode?,
        chargerConnected: Bool,
        systemIsDischargingToLimit: Bool = false,
        systemIsHoldingBelowLimit: Bool = false,
        systemIsChargingPastLimit: Bool = false,
        isHoldingFullChargeUntilUnplugged: Bool = false,
        isAwaitingModeForChargerChange: Bool = false,
        sailingResumeLevel: Int? = nil
    ) {
        self.mode = mode
        self.userTempOverride = userTempOverride
        self.chargerConnected = chargerConnected
        self.systemIsDischargingToLimit = systemIsDischargingToLimit
        self.systemIsHoldingBelowLimit = systemIsHoldingBelowLimit
        self.systemIsChargingPastLimit = systemIsChargingPastLimit
        self.isHoldingFullChargeUntilUnplugged = isHoldingFullChargeUntilUnplugged
        self.isAwaitingModeForChargerChange = isAwaitingModeForChargerChange
        self.sailingResumeLevel = sailingResumeLevel
    }

    /// This state with the charger connection replaced and every other field carried across.
    /// - Parameter awaitingMode: true only when the connection is published ahead of the mode;
    ///   an applier publishing the connection beside the mode it derived passes `false`.
    public func withChargerConnected(_ connected: Bool, awaitingMode: Bool = false) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: userTempOverride,
            chargerConnected: connected,
            systemIsDischargingToLimit: systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: awaitingMode,
            sailingResumeLevel: sailingResumeLevel
        )
    }

    /// This state with the override replaced and every other field carried across.
    public func replacingOverride(_ override: UserTempChargingMode?) -> AppChargingMode {
        replacingOverride(override, mode: mode)
    }

    /// This state with `ending` cleared — and `mode` published with it, where given — or this
    /// state unchanged where `ending` is no longer the override in force: an override armed
    /// while the end of the last one was being worked out is not cleared with it.
    public func endingOverride(_ ending: UserTempChargingMode, mode newMode: ChargingMode?) -> AppChargingMode {
        endingOverride(ending, with: OverrideEnd(mode: newMode))
    }

    /// This state with `ending` replaced by what `end` puts in its place — nothing, or the
    /// discharge a discharge pause resumes — and the mode and drain flag `end` publishes with
    /// it, in one publish; or this state unchanged where `ending` is no longer in force.
    public func endingOverride(_ ending: UserTempChargingMode, with end: OverrideEnd) -> AppChargingMode {
        guard userTempOverride == ending else { return self }
        return AppChargingMode(
            mode: end.mode ?? mode,
            userTempOverride: end.restoring,
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: end.systemIsDischargingToLimit ?? systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: isAwaitingModeForChargerChange,
            // An end that publishes a mode publishes the hold with it, none included; one that
            // publishes nothing leaves it, with the mode, for the pass.
            sailingResumeLevel: end.mode != nil ? end.sailingResumeLevel : sailingResumeLevel
        )
    }

    /// This state with the override and the mode replaced in one publish — see
    /// `ChargingAheadOfApply.modeOnEndingOverride`.
    public func replacingOverride(_ override: UserTempChargingMode?, mode newMode: ChargingMode) -> AppChargingMode {
        AppChargingMode(
            mode: newMode,
            userTempOverride: override,
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: isAwaitingModeForChargerChange,
            sailingResumeLevel: sailingResumeLevel
        )
    }
}

public struct UserTempChargingMode: Equatable, Identifiable, RawRepresentable, Sendable {
    public let limit: Int

    /// Whether "Inhibit Charging" armed this override, rather than a request for a target.
    ///
    /// The limit alone cannot say: an inhibit is an override at the battery's level, and so
    /// is a Shortcuts request that happens to name it. The two are held differently where
    /// Apple's charge limit is the mechanism — see `ManualInhibit` — so the request carries
    /// what it is. Carried on the value rather than remembered beside it in the charging
    /// manager because the value is what reaches each status pass: a record kept elsewhere
    /// could be cleared by a pass still holding the override from before the click.
    ///
    /// Part of equality, so an inhibit replacing a plain override at the same limit is a
    /// change. Not part of `rawValue`, which is the limit as it has always been.
    public let isInhibit: Bool

    /// Whether this inhibit was armed while the battery was discharging on the charger — macOS
    /// draining it to the limit, or BatFi's own discharge — so it pauses a discharge rather
    /// than a charge: "Pause Discharging", ended by "Resume Discharging", and told as
    /// "Discharging paused at N%". Held exactly as any other inhibit is (`ManualInhibit`); only
    /// what the user is told, and what resuming goes back to, differ. Never set without
    /// `isInhibit`.
    public let pausesDischarge: Bool

    /// The plain override a discharge pause replaced, which "Resume Discharging" puts back —
    /// "Run on Battery", or a Shortcuts limit below the battery. Nil where the discharge was
    /// the charge limit's own (macOS draining to it, or BatFi discharging to it), which ending
    /// the pause resumes by itself.
    public let resumesOverrideLimit: Int?

    public var id: Int { limit }

    public var rawValue: Int { limit }

    public init(limit: Int) {
        self.init(limit: limit, isInhibit: false)
    }

    public init(limit: Int, isInhibit: Bool, pausesDischarge: Bool = false, resumesOverrideLimit: Int? = nil) {
        self.limit = limit
        self.isInhibit = isInhibit
        self.pausesDischarge = isInhibit && pausesDischarge
        self.resumesOverrideLimit = isInhibit && pausesDischarge ? resumesOverrideLimit : nil
    }

    /// The override "Resume Discharging" puts back, or nil where ending this one is enough.
    public var overrideToResume: UserTempChargingMode? {
        resumesOverrideLimit.map(UserTempChargingMode.init(limit:))
    }

    /// Spelled out because `RawRepresentable` supplies an `==` on `rawValue` that wins over
    /// the synthesized one, and that would compare the limit alone.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.limit == rhs.limit
            && lhs.isInhibit == rhs.isInhibit
            && lhs.pausesDischarge == rhs.pausesDischarge
            && lhs.resumesOverrideLimit == rhs.resumesOverrideLimit
    }

    public init?(rawValue: Int) {
        guard rawValue <= 100 && rawValue >= 0 else { return nil }
        self.init(rawValue: rawValue)
    }
}


public enum ChargingMode: String, Equatable, Identifiable, Sendable {
    case initial
    case charging
    case inhibit
    case forceDischarge

    public var id: String { rawValue }
}
