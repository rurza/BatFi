//
//  AutoLowPowerModeEvaluation.swift
//  BatFi
//
//  The glue between `AutoLowPowerModePolicy` and the manager that carries its answers out:
//  when the helper is worth asking at all, how a reconcile chains into a fresh decision,
//  which side effects a decision stands for, and what quitting does. Pure, like the policy,
//  so the manager is left with calls and ordering and nothing to decide.
//

import Foundation

public enum AutoLowPowerModeEvaluation {
    /// Whether an evaluation should ask the helper for the live setting before deciding.
    ///
    /// Asking is an XPC round trip, and against a helper too old to know the call it stalls
    /// for the watchdog's fifteen seconds and takes the shared connection down with it. So
    /// it is asked only where the answer can change what happens:
    /// - a record is held — every way of giving Low Power Mode back, including the feature
    ///   being switched off or the licence lost, starts from the live value;
    /// - or the feature could engage right now, which takes a valid licence.
    ///
    /// Everywhere else the policy decides nothing whatever the live value is, and deciding
    /// without it still resets the hand-back latch on the charger. That is also why there is
    /// no read "on the first evaluation after launch" beyond these two: a launch reconcile
    /// only has something to do when a record survived, which the first clause covers.
    public static func needsLiveState(_ input: AutoLowPowerModePolicy.Input) -> Bool {
        if input.record != nil { return true }
        return input.mayEngage
            && input.onBattery
            && !input.yieldedUntilCharge
            && input.batteryLevel > 0
            && input.batteryLevel <= input.threshold
    }

    /// The decisions one evaluation carries out, in order.
    ///
    /// A reconcile — the first evaluation after launch, or after the helper comes back —
    /// goes through `reconcileAtLaunch`, because a helper that exits restores the previous
    /// value on its way out, and plain `decide` would read that restore as the user taking
    /// over and latch BatFi out until the next charge. Where the reconcile clears such a
    /// stale record, the policy is asked again at once, with the record gone and the latch
    /// the reconcile left, so BatFi turns Low Power Mode back on now if it still should
    /// rather than at the next trigger. Clearing a record has no failure to wait on, so the
    /// second decision can be made before the first is applied.
    public static func decisions(
        _ input: AutoLowPowerModePolicy.Input,
        reconcile: Bool
    ) -> [AutoLowPowerModePolicy.Decision] {
        guard reconcile else { return [AutoLowPowerModePolicy.decide(input)] }
        let first = AutoLowPowerModePolicy.reconcileAtLaunch(input)
        guard first.reason == .alreadyRestoredByHelper else { return [first] }
        var next = input
        next.record = nil
        next.yieldedUntilCharge = first.yieldedUntilCharge
        return [first, AutoLowPowerModePolicy.decide(next)]
    }

    /// The side effects a decision stands for. The hand-back latch is not part of it: every
    /// decision carries one, and the manager stores it whatever the step.
    public enum Step: Equatable, Sendable {
        /// Store the record, then write low power, then arm the helper and tell the user —
        /// once per discharge, see `announcement`.
        ///
        /// A write that fails keeps the record, and owes a reconcile, rather than forgetting
        /// it: the reply may be all that was lost. A write that landed with no record left
        /// would leave Low Power Mode on for good, taken for the user's own choice. The next
        /// reading settles it — see `AutoLowPowerModeHelperSession.writeMayHaveLanded()`.
        case engage(AutoLowPowerModeRecord)
        /// Write `value` back, forget `record` only once that succeeded, then disarm.
        case restore(value: UInt8, record: AutoLowPowerModeRecord)
        /// Forget the record without writing, then disarm. Either the user took Low Power
        /// Mode over, or the setting is back to what BatFi found: the helper gave it back as
        /// it exited, or an engage write never landed.
        case forget
        /// Hand the held record to the helper again. After a healthy edge the helper may be
        /// a new process with nothing armed.
        case rearm(AutoLowPowerModeRecord)
        case none
    }

    /// - Parameters:
    ///   - heldRecord: the record held when the decision was made.
    ///   - afterReconcile: whether the decision came out of a reconcile against a helper
    ///     that may have just started.
    public static func step(
        for decision: AutoLowPowerModePolicy.Decision,
        heldRecord: AutoLowPowerModeRecord?,
        afterReconcile: Bool
    ) -> Step {
        switch (decision.write, decision.record) {
        case let (.some, .set(record)):
            return .engage(record)
        case let (.some(value), .clear):
            // A write with nothing held to take it from has no record to forget afterwards
            // and nothing to say it is BatFi's to write. The policy never produces one.
            guard let heldRecord else { return .none }
            return .restore(value: value, record: heldRecord)
        case (nil, .clear):
            return .forget
        case (nil, .keep):
            guard afterReconcile, let heldRecord else { return .none }
            return .rearm(heldRecord)
        case (.some, .keep), (nil, .set):
            return .none
        }
    }

    /// Whether to tell the user Low Power Mode went on, and what to remember about it.
    public struct Announcement: Equatable, Sendable {
        /// Post the notification.
        public var post: Bool
        /// Whether the user has been told during this discharge, as it stands afterwards.
        public var announcedThisDischarge: Bool

        public init(post: Bool, announcedThisDischarge: Bool) {
            self.post = post
            self.announcedThisDischarge = announcedThisDischarge
        }
    }

    /// Once per discharge. Quitting gives Low Power Mode back and the next launch turns it
    /// on again — after every update, say — and so does a reconcile after the helper came
    /// back; none of that is news to someone told the first time. Being on the charger ends
    /// the discharge, and the next time the battery runs low is announced afresh.
    ///
    /// So does a charge BatFi did not see — the Mac shut down low and charged, say — or the
    /// whole of the next discharge would go unannounced. On the battery the charge only
    /// falls, so the discharge is taken to be over wherever the level is
    /// `AutoLowPowerModePolicy.hysteresis` points or more above the threshold: the line the
    /// policy gives Low Power Mode back at. A relaunch below the threshold is below it, and
    /// stays quiet. A charge that stops short of it is not told apart from the discharge
    /// going on. A threshold lowered past it ends the discharge as a charge would: Low Power
    /// Mode is given back there, and turning it on again at the new threshold is announced.
    ///
    /// - Parameters:
    ///   - onBattery: as the policy's input has it.
    ///   - batteryLevel: as the policy's input has it. 0, a level not read yet, says nothing
    ///     about a charge.
    ///   - threshold: as the policy's input has it.
    ///   - engaged: whether an engage write just landed.
    ///   - announcedThisDischarge: what was remembered before.
    public static func announcement(
        onBattery: Bool,
        batteryLevel: Int,
        threshold: Int,
        engaged: Bool,
        announcedThisDischarge: Bool
    ) -> Announcement {
        guard onBattery else { return Announcement(post: false, announcedThisDischarge: false) }
        let dischargeEnded = batteryLevel > 0 && batteryLevel >= threshold + AutoLowPowerModePolicy.hysteresis
        let announced = announcedThisDischarge && !dischargeEnded
        guard engaged else { return Announcement(post: false, announcedThisDischarge: announced) }
        return Announcement(post: !announced, announcedThisDischarge: true)
    }

    public enum QuitStep: Equatable, Sendable {
        /// Still BatFi's: write the previous value back, forget the record, disarm.
        case restore
        /// Already the value BatFi found — its write never landed, or was given back:
        /// forget the record, disarm, write nothing, and leave the hand-back latch alone.
        case forget
        /// The user changed it: forget the record, disarm, write nothing, and stay out until
        /// the next charge.
        case handBack
        /// No reading: act on nothing, and leave the helper armed — it checks ownership
        /// itself and gives the value back as it exits.
        case leaveToHelper

        /// Why, for the log, spelled the way `AutoLowPowerModePolicy.Reason` is.
        public var reason: String {
            switch self {
            case .restore: "restoredAtQuit"
            case .forget: "previousValueInEffect"
            case .handBack: AutoLowPowerModePolicy.Reason.handedBackToUser.rawValue
            case .leaveToHelper: AutoLowPowerModePolicy.Reason.liveStateUnknown.rawValue
            }
        }
    }

    /// What quitting does with a record still held. Read the same way a reconcile reads it,
    /// so the record an engage kept after its write failed is not mistaken for the user's
    /// change when the write never landed.
    public static func quitStep(record: AutoLowPowerModeRecord, live: PowerModeBySource?) -> QuitStep {
        guard let live, live.battery != nil else { return .leaveToHelper }
        if AutoLowPowerModePolicy.isStillOwned(record, live: live) { return .restore }
        if AutoLowPowerModePolicy.showsPreviousValue(record, live: live) { return .forget }
        return .handBack
    }
}

/// What the manager knows about the helper it is talking to.
///
/// A reconcile is owed per helper process rather than per launch, because a helper that
/// exits restores the previous value on its way out and the one started after it has
/// nothing armed. A helper becoming healthy is one sign of that. A dropped connection is the
/// other, and the only one when a helper exits and is started again by the next call: the
/// ping that follows succeeds, so the health never leaves "healthy". (The client's watchdog
/// teardown does not report a dropped connection, so a helper that merely stalls does not
/// count.) An engage write that failed owes one too, because a failed write may still have
/// landed — it is the reply that was lost.
///
/// The asking stops after a *slow* "unknown" — one that took `slowAnswer` or longer, which
/// is what an older helper that lacks the call looks like: it drops the message, and the
/// answer is the watchdog tearing the shared connection down fifteen seconds later, failing
/// whatever else was in flight. It resumes when a helper next becomes healthy, which is what
/// an upgrade or a restart looks like, and not on a dropped connection, or a helper that
/// cannot answer would be asked again after every one. A *quick* "unknown" — `pmset` failing
/// once, a helper on its way out — stops nothing: asking again on the next trigger costs
/// nothing.
///
/// Answers are filed against the `mark` taken when they were asked, so an evaluation that
/// began before any of these events cannot speak for what came after it.
public struct AutoLowPowerModeHelperSession: Equatable, Sendable {
    /// How long an "unknown" has to have taken to count as the old-helper stall. Well past
    /// any `pmset` the helper runs, and well short of the client's fifteen-second watchdog.
    public static let slowAnswer: Duration = .seconds(10)

    public struct Mark: Equatable, Sendable {
        fileprivate let helper: Int
        fileprivate let reconcile: Int
    }

    private var helperGeneration = 0
    private var reconcileGeneration = 0
    private var stalledIn: Int?
    private var reconciledIn: Int?

    public init() {}

    /// Taken before asking the helper, and handed back with what it answered.
    public var mark: Mark { Mark(helper: helperGeneration, reconcile: reconcileGeneration) }

    /// Whether the helper may be asked for the live setting.
    public var mayAsk: Bool { stalledIn != helperGeneration }

    /// Whether the next evaluation that reads the live setting should reconcile.
    public var needsReconcile: Bool { reconciledIn != reconcileGeneration }

    public mutating func helperBecameHealthy() {
        helperGeneration += 1
        reconcileGeneration += 1
    }

    public mutating func connectionWasLost() {
        reconcileGeneration += 1
    }

    /// An engage write failed, and may have landed all the same.
    public mutating func writeMayHaveLanded() {
        reconcileGeneration += 1
    }

    /// - Parameter elapsed: how long the helper took to answer.
    public mutating func helperAnsweredUnknown(at asked: Mark, after elapsed: Duration) {
        guard asked.helper == helperGeneration, elapsed >= Self.slowAnswer else { return }
        stalledIn = asked.helper
    }

    public mutating func reconciled(at asked: Mark) {
        guard asked.reconcile == reconcileGeneration else { return }
        reconciledIn = asked.reconcile
    }
}
