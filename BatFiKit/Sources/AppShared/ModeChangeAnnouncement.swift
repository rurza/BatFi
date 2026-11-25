//
//  ModeChangeAnnouncement.swift
//
//
//  Which charging-state changes are worth a "New mode" banner.
//
//  On a mechanism that drains to the limit itself, `.inhibit` covers several things macOS
//  does on its own — charging past the limit for calibration, draining down to it, holding
//  charge below it — and the menu names each. They are real and the label should follow
//  them, but none is something the user did or can stop, and macOS moves between them often:
//  MPX-43 had a banner every minute or two during a calibration plateau. So a move between
//  those sub-states stays on the label and off Notification Center. Everything else — BatFi
//  starting or stopping a charge, a discharge, an override, the charge-to-full hold, a new
//  limit — still announces.
//
//  Here rather than in `NotificationsManager` because that target has no tests.
//

import Foundation

public enum ModeChangeAnnouncement {
    /// A charging state as it would be announced: the mode and the limit the sentence names.
    public struct Seen: Equatable, Sendable {
        public let mode: AppChargingMode
        public let limit: Int
        public let automationRuleName: String?

        public init(mode: AppChargingMode, limit: Int, automationRuleName: String?) {
            self.mode = mode
            self.limit = limit
            self.automationRuleName = automationRuleName
        }
    }

    /// What the announcer does with a charging state as it arrives.
    public enum Consideration: Equatable, Sendable {
        /// Render it and let `Memory.decide` judge it.
        case announce
        /// A state that is never announced; `Memory.skip` it.
        case skip
        /// The charger was plugged in but the mode for it is not known yet. Neither announced
        /// nor remembered: the mode follows, and it is the one to announce.
        case awaitMode
    }

    /// Whether `mode` is announced, skipped, or waited on.
    ///
    /// An unplug published ahead of its mode is skipped like any other: it ends the charging
    /// session whatever the mode says. A plug-in published ahead of its mode is waited on,
    /// because the mode it carries is the one from before the charger came in — see
    /// `AppChargingMode.isAwaitingModeForChargerChange`. Everything else the user asks for —
    /// an inhibit, a resume, a raise — is announced at once, as the state asked for.
    public static func consideration(of mode: AppChargingMode, manageCharging: Bool) -> Consideration {
        guard mode.mode != .initial, manageCharging, mode.chargerConnected else { return .skip }
        return mode.isAwaitingModeForChargerChange ? .awaitMode : .announce
    }

    /// Whether going from `previous` to `current` is only macOS moving between its own
    /// sub-states of the held mode, with nothing the user would recognise as a change.
    ///
    /// The limit and the rule that set it are part of the question: a sub-state change that
    /// arrives with a new limit is most likely the user or an automation lowering it, and that
    /// is news. A pair whose sub-state did not change is not this function's business — the
    /// text dedupe downstream already handles it, and lets a changed limit through.
    /// A change of only the sailing resume level — the hold named over an inhibit already
    /// shown, or moved by a new limit — is quiet whatever the limit did: sailing posts nothing
    /// of its own, and a limit change under an unchanged mode published nothing before it.
    public static func isQuietChange(from previous: Seen?, to current: Seen) -> Bool {
        if let previous, previous.mode.sailingResumeLevel != current.mode.sailingResumeLevel,
           previous.mode.withoutSailingHold == current.mode.withoutSailingHold {
            return true
        }
        guard let previous,
              previous.limit == current.limit,
              previous.automationRuleName == current.automationRuleName,
              let from = systemSubState(of: previous.mode),
              let to = systemSubState(of: current.mode)
        else { return false }
        return from != to
    }

    /// What the announcer remembers between charging states, and the decision it makes with it.
    ///
    /// Two memories with different lifetimes. The last state *seen* feeds `isQuietChange`, and
    /// is forgotten whenever the stream passes through a state that is never announced —
    /// unplugged, management off, initial — so the quiet rule only spans one unbroken stretch
    /// on the charger. The last sentence *posted* is the text dedupe, and lasts one charging
    /// session: it is forgotten when the charger is unplugged, and only then.
    ///
    /// Outliving the unplug was the bug. Plug in below the limit, unplug, plug in again, and
    /// the second "Charging to the limit / The limit is 80%" was the same sentence as the
    /// first and was dropped — banners "only sometimes, then never". Each plug-in is news.
    ///
    /// Management going off and on, or the mode passing through `.initial`, does *not* end
    /// the session. The charger never left, so the sentence would be a repeat of one still
    /// true; and `.initial` reports no charger whatever is plugged in, so reading it as an
    /// unplug would repost on a mode that only paused.
    ///
    /// The first announceable state after observing starts — a launch, or the notification
    /// setting turned back on — is a baseline: remembered as seen and as said, and not posted.
    /// It is the state BatFi found, not a change. Reported from hardware on beta 246: right
    /// after a Sparkle relaunch, "New mode: Inhibiting charging" for a battery that had sat
    /// above the limit on the charger before and after the update. Only a seen unplug drops
    /// the baseline, because then the next plug-in is a change BatFi watched happen. A launch
    /// with management off keeps it, so turning management on is not announced: the user's
    /// own act, on a charger that never left, whose result the menu shows at once.
    public struct Memory: Sendable {
        public enum Decision: Equatable, Sendable {
            case post
            /// The first announceable state since observing started: what BatFi found, not a
            /// change. Remembered as posted.
            case baseline
            /// macOS only moved between its own sub-states of the held mode (MPX-43).
            case quietSubStateChange
            /// The same sentence was the last thing posted this charging session.
            case repeatedText
        }

        private struct Text: Equatable, Sendable {
            let title: String
            let body: String
        }

        private var lastSeen: Seen?
        private var lastAnnounced: Text?
        private var awaitingBaseline = true

        public init() {}

        /// The stream passed through a state that is never announced.
        public mutating func skip(_ mode: AppChargingMode) {
            lastSeen = nil
            if mode.mode != .initial, !mode.chargerConnected {
                lastAnnounced = nil
                awaitingBaseline = false
            }
        }

        /// Observing stopped; the next announceable state is a new baseline.
        public mutating func forget() {
            lastSeen = nil
            lastAnnounced = nil
            awaitingBaseline = true
        }

        /// Whether `seen`, rendered as `title` and `body`, should be posted. A `.post` is
        /// remembered as posted, so the caller must post it.
        public mutating func decide(_ seen: Seen, title: String, body: String) -> Decision {
            let text = Text(title: title, body: body)
            if awaitingBaseline {
                awaitingBaseline = false
                lastSeen = seen
                lastAnnounced = text
                return .baseline
            }
            let isQuiet = ModeChangeAnnouncement.isQuietChange(from: lastSeen, to: seen)
            lastSeen = seen
            guard !isQuiet else { return .quietSubStateChange }
            guard text != lastAnnounced else { return .repeatedText }
            lastAnnounced = text
            return .post
        }
    }

    private enum SubState: Equatable {
        case plain, toppingUp, draining, holdingBelowLimit
    }

    /// Which sub-state of a plugged-in, BatFi-chosen `.inhibit` this is, or nil for anything
    /// that is not one. In `stateDescription`'s precedence order, so the sub-state is the one
    /// the label shows.
    private static func systemSubState(of mode: AppChargingMode) -> SubState? {
        guard mode.mode == .inhibit,
              mode.chargerConnected,
              mode.userTempOverride == nil,
              !mode.isHoldingFullChargeUntilUnplugged
        else { return nil }
        if mode.systemIsChargingPastLimit { return .toppingUp }
        if mode.systemIsDischargingToLimit { return .draining }
        if mode.systemIsHoldingBelowLimit { return .holdingBelowLimit }
        return .plain
    }
}

private extension AppChargingMode {
    var withoutSailingHold: AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: userTempOverride,
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: isAwaitingModeForChargerChange
        )
    }
}
