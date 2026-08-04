//
//  ChargeControlDisclosure.swift
//
//
//  What this Mac can and cannot do about charging, and therefore what the user has to be
//  told about it.
//
//  Lives here, beside `AppliedChargeLimit` and `ForceDischargeKeyShape`, and for the same
//  reason: these are decisions, they have edge cases worth pinning, and `Shared` is the
//  only module the test target can reach. Buried in a SwiftUI `body` the rule that decides
//  whether a user learns their 55% limit is not in force would be untestable — and the
//  machines it is wrong on are the ones nobody has.
//
//  Nothing in this file may branch on a macOS version. Every answer comes from the
//  resolved `ChargeBackend` and from capabilities the helper probed per key.
//

import Foundation

/// One statement the Charging pane owes the user about how charging is controlled on
/// *this* Mac.
///
/// Values rather than strings: the wording lives in `L10n` and the rendering in
/// `Settings`, while the decision of *which* statements are true lives here.
public enum ChargeControlDisclosure: Equatable, Sendable {
    /// No usable mechanism at all — BatFi cannot *limit* charging on this firmware.
    ///
    /// `forceDischargeStillAvailable` is carried for exactly the reason
    /// `pausingChargingUnavailable` carries it, and this case needed it just as much:
    /// `CHIE` is probed independently of the backend, precisely so "Run on Battery"
    /// survives where charge limiting is gone, and `.unsupported` is reachable with it
    /// working. Without the flag this Mac was told BatFi "can't control charging" full
    /// stop, which reads as "the app does nothing here" to a user whose Run on Battery
    /// works perfectly.
    case chargingControlUnavailable(forceDischargeStillAvailable: Bool)

    /// BatFi is driving Apple's Manual Charge Limit, which only accepts 80–100%.
    case usingSystemChargeLimit

    /// A limit *below the mechanism's floor* was asked for, so `applied` — the floor — is
    /// in force instead. Carried as a number so the copy can name the value actually in
    /// effect rather than gesture at it.
    ///
    /// Strictly the floor clamp, never a round-up: only here is it true that limits below
    /// the floor cannot be applied at all and that the applied value is the lowest the
    /// mechanism accepts. A request of 87 landing on 90 is `.limitRoundedUp`, where both
    /// of those sentences would be false.
    case limitRaisedToSystemMinimum(applied: Int)

    /// A limit the mechanism could have expressed *in principle* — at or above its floor —
    /// but not exactly, so it was rounded up to the next accepted step. 87 becomes 90, 97
    /// becomes 100.
    ///
    /// Not a corner case: `ChargingManager.inhibitCharging()` sets a temporary limit at the
    /// current battery level, an arbitrary integer, so any stop-charging click at a
    /// non-multiple of 5 lands here. Both numbers are carried because the copy has to name
    /// what was asked for as well as what is in force — without them the pane can only
    /// repeat the floor-clamp sentence, which is false for every one of these.
    case limitRoundedUp(requested: Int, applied: Int)

    /// BatFi has written the value the user can see in System Settings › Battery, and
    /// owes them a restore on quit. The disclosure the whole snapshot/restore machinery
    /// exists to justify: `setMCLLimit:` mutates a control the user did not expect BatFi
    /// to touch.
    case managingSystemSettingsLimit

    /// BatFi is applying no limit at all, because it could not first record the user's
    /// own System Settings value and will not change a value it might not be able to put
    /// back. Without this the refusal reaches only the helper log.
    case limitNotAppliedWithoutSnapshot

    /// The Mac's own firmware is enforcing the user's limit, and goes on enforcing it with
    /// no BatFi process running. The lead statement under `.firmwareRange`, and the one
    /// piece of genuinely *good* news any of these carry — it is stronger than what BatFi
    /// can do for itself, and burying it under the two limitations below would misdescribe
    /// this Mac as the worse one.
    case firmwareEnforcedLimit

    /// The battery will sit below the limit sometimes, on purpose. A band is not a ceiling:
    /// the firmware lets the charge fall by `hysteresis` points before it charges again, so
    /// a user who set 80% and watches 75% is looking at the mechanism working.
    ///
    /// The number is carried rather than written into the copy because it is a property of
    /// the band, stated once in `FirmwareChargeRange.hysteresis`, and a sentence naming a
    /// different figure than the one actually written to the firmware is exactly the kind
    /// of quiet disagreement this pane exists to avoid.
    case batteryMayDipBelowLimit(hysteresis: Int)

    /// BatFi's own charging/holding label is **inferred, not observed**, so it can say
    /// "charging" while the mechanism is holding. Belongs beside `batteryMayDipBelowLimit`
    /// and is emitted immediately after it: that case explains why the *battery* sits below
    /// the limit, and leaves the *label* still asserting something false for the same
    /// stretch of time.
    ///
    /// Precise about what is and is not affected. The limit is enforced exactly and the
    /// battery percentage shown is real; only the charging/holding label is a guess. A user
    /// must not come away thinking the limit is unreliable — that would be a worse error
    /// than the one this discloses.
    ///
    /// Scoped to the mechanism that genuinely does not report when it is holding. See the
    /// `.systemChargeLimit` arm of `disclosures` for why that backend, which looks like it
    /// has the same problem, does not get this sentence.
    case chargingStatusIsInferred

    /// Pausing charging outright cannot engage: the mechanism in force holds charge at a
    /// percentage and has no "stop now" to write. This is why hot-battery protection and
    /// pause-on-sleep do nothing, and it cannot be fixed — only disclosed.
    ///
    /// `heldBy` names the mechanism, because the consequence is identical under both and
    /// the sentence explaining it is not: telling a macOS 27 user that "the macOS charge
    /// limit" is the reason would point them at a setting BatFi is not using.
    ///
    /// `forceDischargeStillAvailable` is carried rather than implied, deliberately.
    /// Force discharge is probed from its own key (`CHIE` outlives both `CHTE` and the
    /// charge-limit keys), so "Run on Battery" can still work on a machine that has lost
    /// charge limiting — and sweeping it into this case would tell a user that a feature
    /// which works is broken.
    case pausingChargingUnavailable(heldBy: LimitHolder, forceDischargeStillAvailable: Bool)

    /// Which mechanism is holding charge at the limit instead of stopping it on request.
    public enum LimitHolder: Equatable, Sendable {
        /// Apple's Manual Charge Limit, the value in System Settings › Battery.
        case macOSChargeLimit
        /// The Mac's own firmware, enforcing the band BatFi handed it. Nothing in System
        /// Settings is involved, so the copy must not send the user there.
        case macFirmware
    }
}

/// Everything the Charging pane knows about charge control, flattened into plain values.
///
/// Deliberately not a view model and deliberately not built from `Defaults`: every input
/// is passed in, so each branch below can be exercised on its own.
public struct ChargeControlFacts: Equatable, Sendable {
    /// The resolved backend. `nil` both before the first diagnostics fetch lands and when
    /// the helper reports a raw value this build does not recognize — in either case the
    /// honest answer is to disclose nothing rather than guess at a mechanism.
    public let backend: ChargeBackend?

    /// Whether BatFi is managing charging at all. With it off BatFi holds no override,
    /// applies no limit and touches nothing, so the disclosures that describe BatFi
    /// *acting* have nothing to describe.
    public let manageCharging: Bool

    /// `ChargingDiagnostics.appliedChargeLimit` — the limit BatFi last put in force
    /// through Apple's Manual Charge Limit, or nil when it holds none.
    public let appliedChargeLimit: Int?

    /// `ChargingDiagnostics.chargeLimitWasRaised`.
    public let chargeLimitWasRaised: Bool

    /// `ChargingDiagnostics.requestedChargeLimit` — what was asked for, beside what was
    /// applied. The flag above says only *that* the value moved; this says which way of
    /// moving it happened, and the two need different words.
    public let requestedChargeLimit: Int?

    /// Whether the helper refused to snapshot the user's own System Settings limit, and
    /// therefore set no limit at all.
    public let systemLimitSnapshotRefused: Bool

    /// Whether PowerUI reports Manual Charge Limit support on this machine.
    public let systemLimitIsSupported: Bool

    /// The charge limit the system reports right now, or nil when it could not be read.
    public let systemLimit: Int?

    /// Whether BatFi is currently holding a temporary MCL override. Under an SMC backend
    /// that override is 100%, which is what neutralizes the system's own limit.
    public let batFiHoldsSystemLimitOverride: Bool

    /// `ChargingDiagnostics.forceDischargeAvailable` — probed from its own key, never
    /// inferred from `backend`.
    public let forceDischargeAvailable: Bool

    /// The "stop charging when the battery is hot" setting (Advanced pane).
    public let hotBatteryProtectionEnabled: Bool

    /// The "pause charging when the Mac goes to sleep" setting (Charging pane).
    public let pauseChargingOnSleepEnabled: Bool

    public init(
        backend: ChargeBackend?,
        manageCharging: Bool,
        appliedChargeLimit: Int?,
        chargeLimitWasRaised: Bool,
        requestedChargeLimit: Int? = nil,
        systemLimitSnapshotRefused: Bool,
        systemLimitIsSupported: Bool,
        systemLimit: Int?,
        batFiHoldsSystemLimitOverride: Bool,
        forceDischargeAvailable: Bool,
        hotBatteryProtectionEnabled: Bool,
        pauseChargingOnSleepEnabled: Bool
    ) {
        self.backend = backend
        self.manageCharging = manageCharging
        self.appliedChargeLimit = appliedChargeLimit
        self.chargeLimitWasRaised = chargeLimitWasRaised
        self.requestedChargeLimit = requestedChargeLimit
        self.systemLimitSnapshotRefused = systemLimitSnapshotRefused
        self.systemLimitIsSupported = systemLimitIsSupported
        self.systemLimit = systemLimit
        self.batFiHoldsSystemLimitOverride = batFiHoldsSystemLimitOverride
        self.forceDischargeAvailable = forceDischargeAvailable
        self.hotBatteryProtectionEnabled = hotBatteryProtectionEnabled
        self.pauseChargingOnSleepEnabled = pauseChargingOnSleepEnabled
    }

    /// Reads the helper's snapshot. An unrecognized backend string lands on `nil`, which
    /// discloses nothing — the same fail-closed rule
    /// `ChargingDiagnostics.systemChargeLimitIsHoldingCharge` uses.
    public init(
        diagnostics: ChargingDiagnostics?,
        manageCharging: Bool,
        hotBatteryProtectionEnabled: Bool,
        pauseChargingOnSleepEnabled: Bool
    ) {
        // Spelled out one local at a time rather than as one call full of `??` and
        // optional chains. The single expression was enough to defeat the type checker
        // ("unable to type-check this expression in reasonable time"), and this shape is
        // both instant to compile and easier to read.
        let mcl: MCLStatus? = diagnostics?.mcl
        let resolvedBackend: ChargeBackend?
        if let rawBackend = diagnostics?.backend {
            resolvedBackend = ChargeBackend(rawValue: rawBackend)
        } else {
            resolvedBackend = nil
        }
        let applied: Int? = diagnostics?.appliedChargeLimit
        let wasRaised: Bool = diagnostics?.chargeLimitWasRaised ?? false
        let requested: Int? = diagnostics?.requestedChargeLimit
        let refused: Bool = mcl?.snapshotRefused ?? false
        let mclSupported: Bool = mcl?.supported ?? false
        let currentSystemLimit: Int? = mcl?.systemLimit
        let holdsOverride: Bool = mcl?.batFiHasActiveOverride ?? false
        // Two levels of optional collapse to one answer, and `false` is the right default
        // for both: "the helper has not answered yet" and "the helper could not probe" are
        // equally poor grounds for telling a user that a feature still works.
        let forceDischarge: Bool = (diagnostics?.forceDischargeAvailable ?? nil) ?? false

        self.init(
            backend: resolvedBackend,
            manageCharging: manageCharging,
            appliedChargeLimit: applied,
            chargeLimitWasRaised: wasRaised,
            requestedChargeLimit: requested,
            systemLimitSnapshotRefused: refused,
            systemLimitIsSupported: mclSupported,
            systemLimit: currentSystemLimit,
            batFiHoldsSystemLimitOverride: holdsOverride,
            forceDischargeAvailable: forceDischarge,
            hotBatteryProtectionEnabled: hotBatteryProtectionEnabled,
            pauseChargingOnSleepEnabled: pauseChargingOnSleepEnabled
        )
    }
}

public extension ChargeControlFacts {
    /// Whether either setting the user has switched on needs charging to actually *stop*
    /// — the thing `ChargeBackend.canPauseChargingOnDemand` answers, and which neither
    /// `.systemChargeLimit` nor `.firmwareRange` can do. Gated on `manageCharging`
    /// because with management off neither setting runs at all, so warning about them
    /// would describe an absence the user already has.
    var pausingChargingIsExpected: Bool {
        manageCharging && (hotBatteryProtectionEnabled || pauseChargingOnSleepEnabled)
    }

    /// What the Charging pane must say, in the order it should be read.
    ///
    /// Exhaustive over `ChargeBackend` with no `default:` arm, so a future case has to be
    /// answered here rather than silently inheriting whatever the last one said.
    var disclosures: [ChargeControlDisclosure] {
        // Not resolved yet, or resolved to something this build does not know. Saying
        // nothing is the only honest answer: every statement below is a claim about a
        // specific mechanism.
        guard let backend else { return [] }

        switch backend {
        case .chte, .legacyCH0BC:
            // The mechanism honours the user's value exactly. There is nothing to
            // disclose, and inventing something here is how the pane would start warning
            // every working Mac about a problem it does not have.
            return []

        case .firmwareRange:
            // The firmware enforces the user's own value, below 80% included, and BatFi
            // does not touch System Settings to do it — so none of the system-limit
            // statements apply. What this mechanism *does* owe the user is the two ways
            // it behaves visibly differently from an inhibit, and it owes them in that
            // order: the limit is enforced by the firmware and survives sleep, which is
            // better than anything BatFi can do for itself, and only then what it costs.
            //
            // Nothing at all with management off. BatFi releases the band then, so every
            // sentence below would describe a limit that is not in force.
            guard manageCharging else { return [] }

            var disclosures: [ChargeControlDisclosure] = [
                .firmwareEnforcedLimit,
                // Read from the same constant the engage sequence encodes into `bfE0`, so
                // the figure the pane names and the figure the firmware is given cannot
                // come apart.
                .batteryMayDipBelowLimit(hysteresis: FirmwareChargeRange.hysteresis),
                // Immediately after, because it is the other half of the same fact. The dip
                // row explains the battery; this one explains the label, which is wrong for
                // the same stretch of time and in a place the user looks far more often
                // than this pane — `ChargingManager` infers the mode by comparing the
                // battery level against the limit, and the menu bar and the charging
                // notifications both read it.
                .chargingStatusIsInferred,
            ]

            // The one thing that genuinely stopped working, and only for a user who asked
            // for it. `pausingChargingIsExpected` is the same gate `.systemChargeLimit`
            // uses; the gap is identical and so is the rule about when to mention it.
            if pausingChargingIsExpected {
                disclosures.append(
                    .pausingChargingUnavailable(
                        heldBy: .macFirmware,
                        forceDischargeStillAvailable: forceDischargeAvailable
                    )
                )
            }

            return disclosures

        case .unsupported:
            // Said with management on or off, unlike every other arm. This is not a
            // description of what BatFi is doing, it is a statement about what this Mac
            // can do — turning charge management off does not give the firmware a charge
            // limit key back.
            return [.chargingControlUnavailable(forceDischargeStillAvailable: forceDischargeAvailable)]

        case .systemChargeLimit:
            // Nothing at all with management off, the same guard `.firmwareRange` carries
            // above. `restoreSystemDefaults()` has released the adopted limit and cleared
            // `appliedChargeLimit` by then, so "BatFi is using the macOS charge limit"
            // describes a limit BatFi is not holding. If a statement is ever wanted here
            // with management off it has to be in the capability voice, not the present
            // progressive.
            guard manageCharging else { return [] }

            // **Deliberately no `.chargingStatusIsInferred` here**, and not by reflex — the
            // question was asked directly, because this backend looks like it has the same
            // problem and the answer is that it does not have the same *cause*.
            //
            // Under the firmware range nothing reports when charge is being held, so
            // BatFi's label can only ever be a guess. Here the firmware does report it, in
            // `CHNC` bit 24, and BatFi already reads it —
            // `ChargingDiagnostics.systemChargeLimitIsHoldingCharge` is that reading, and
            // the MagSafe LED is already driven from it. The honest sentence for this Mac
            // is therefore not "BatFi can't know"; the signal exists.
            //
            // BatFi's *mode* can still be wrong here, in the other direction: a limit
            // raised from 55% to 80% makes `updateStatus` report `.inhibit` from 55%
            // upward while the hardware charges on. That is worth fixing rather than
            // disclosing — the signal to fix it with is already in this class — and the
            // limit disclosures below already tell this user the number in force. Writing
            // "BatFi can't tell whether it's charging" here would be false and would spend
            // the user's trust on a bug.
            var disclosures: [ChargeControlDisclosure] = [.usingSystemChargeLimit]

            if systemLimitSnapshotRefused {
                // No limit is being applied at all, so the raised-limit and
                // managing-System-Settings statements would both be false. This one
                // replaces them rather than joining them.
                disclosures.append(.limitNotAppliedWithoutSnapshot)
            } else if let applied = appliedChargeLimit {
                // Driven by the helper's own record of what it put in force, never by
                // recomputing the rounding app-side: the value actually requested can be
                // an automation limit or a temporary override rather than the slider, and
                // a second implementation of the rounding would be free to disagree with
                // the one that ran.
                //
                // The flag says only that the value moved up. Which *kind* of raise it was
                // decides the words: a request below the floor genuinely cannot be applied
                // and the floor genuinely is the lowest value accepted, while a request of
                // 87 landing on 90 makes both of those sentences false. Only the requested
                // value tells them apart, so a raise arriving without one names nothing —
                // the same fail-closed rule an applied-less raise already follows. In a
                // matched install that cannot happen: both numbers come from the same
                // `AppliedChargeLimit` and cross the boundary together.
                if chargeLimitWasRaised, let requested = requestedChargeLimit {
                    if requested < ChargeLimitRange.systemChargeLimitLowest {
                        disclosures.append(.limitRaisedToSystemMinimum(applied: applied))
                    } else {
                        disclosures.append(.limitRoundedUp(requested: requested, applied: applied))
                    }
                }
                // Only once a limit is actually held. `appliedChargeLimit` is cleared by
                // every route that ends BatFi's ownership of the system limit, so this
                // cannot claim BatFi is managing a value it has handed back.
                disclosures.append(.managingSystemSettingsLimit)
            }

            if pausingChargingIsExpected {
                disclosures.append(
                    .pausingChargingUnavailable(
                        heldBy: .macOSChargeLimit,
                        forceDischargeStillAvailable: forceDischargeAvailable
                    )
                )
            }

            return disclosures
        }
    }

    /// The system's own charge limit, when it can hold charge back behind BatFi's back —
    /// or nil when it cannot.
    ///
    /// This used to key on `manageCharging && supported && !batFiHasActiveOverride`, a
    /// proxy adopted only because the system's percentage did not cross the XPC boundary.
    /// It does now, so the test is the condition the warning was always trying to express:
    /// **the system limit is below 100**. The old proxy fired on every machine where BatFi
    /// simply had not written an override yet, whatever the system limit actually was.
    ///
    /// Two things narrow it, both load-bearing:
    ///
    /// * **Never under `.systemChargeLimit`.** There the limit BatFi would be warning
    ///   about is the one BatFi itself set, so the warning was unconditionally true and
    ///   actively misleading — it told the user to raise the very value that is applying
    ///   their limit. What that backend owes the user is `.managingSystemSettingsLimit`,
    ///   not a conflict warning.
    /// * **Never under `.unsupported`.** BatFi applies no limit there, so the system's own
    ///   limit is not in conflict with anything; it is the only thing in control, and the
    ///   pane already says BatFi is not.
    ///
    /// `batFiHoldsSystemLimitOverride` survives the rewiring on its own merits rather than
    /// as a stand-in for the value: while BatFi holds its 100% override the system's saved
    /// limit is not in force whatever it reads, so warning about it would describe a cap
    /// that is not applied.
    var conflictingSystemLimit: Int? {
        guard let backend, manageCharging, systemLimitIsSupported else { return nil }

        switch backend {
        case .systemChargeLimit, .unsupported:
            return nil
        case .firmwareRange, .chte, .legacyCH0BC:
            // `.firmwareRange` belongs here, not with the arm above: BatFi applies its
            // limit through the firmware and leaves Apple's Manual Charge Limit alone, so
            // a limit the user left below 100 there really is a second cap acting behind
            // BatFi's back — the exact situation this warning exists for. The override
            // guard is inert under it (`writesMCLOverride` is false, so BatFi never holds
            // one) and costs nothing.
            guard !batFiHoldsSystemLimitOverride else { return nil }
            // An unreadable limit is not evidence of a conflict. Warning on `nil` would
            // put a permanent orange label on every Mac whose PowerUI declines the read.
            guard let systemLimit, systemLimit < 100 else { return nil }
            return systemLimit
        }
    }
}

/// The bounds of the charge-limit slider, which are a property of the mechanism rather
/// than of the app.
public enum ChargeLimitRange {
    /// The lowest limit BatFi offers when the mechanism can express it.
    public static let lowest = 50
    /// The highest limit the slider offers. Unchanged by the backend: Apple's limit
    /// accepts 90, and so do the SMC backends.
    public static let highest = 90
    /// The lowest value Apple's Manual Charge Limit accepts. Measured as (80, 85, 90, 95,
    /// 100); the helper still queries the real list before writing, and this is only what
    /// the slider offers.
    ///
    /// It also decides which raise sentence the pane shows — below it a request was
    /// clamped to the floor, at or above it a request was merely rounded up — and the
    /// floor-clamp string names "80%" in words. Change one and change the other.
    public static let systemChargeLimitLowest = 80

    /// The lowest value the slider may be dragged to on this Mac.
    ///
    /// **Derived from `ChargeBackend.honoursLimitsBelow80` rather than restating it.** This
    /// used to be a second, independent switch over the same enum, which meant the property
    /// its own doc calls "the single most important thing to tell the user" had zero
    /// production callers while the decision it names was taken here — and the two already
    /// disagreed on `.unsupported`. Add a sixth backend that cannot go below 80, answer the
    /// property correctly, and the slider would still have offered 50% under a green suite.
    ///
    /// `.unsupported` is the one case answered here rather than by the property, and the
    /// divergence is deliberate rather than left implicit. The property is false for it —
    /// correctly: nothing there can express any limit, let alone one below 80%. But this
    /// constraint exists to stop the user choosing a value that would be *silently raised
    /// to something else*, and under `.unsupported` nothing is applied at all, so pinning
    /// the slider at 80% would imply 80% is in force when nothing is. That Mac is told the
    /// truth by `.chargingControlUnavailable` instead, and keeps the limit it chose for
    /// whenever it regains a mechanism.
    public static func lowestSelectable(for backend: ChargeBackend?) -> Int {
        // Unresolved is as permissive as `.unsupported`, and for the same reason: no claim
        // has been made about what is in force.
        guard let backend, backend != .unsupported else { return lowest }
        return backend.honoursLimitsBelow80 ? lowest : systemChargeLimitLowest
    }

    /// The value the slider shows, given what the user has configured.
    ///
    /// A stored limit below the floor is shown *at* the floor rather than written back to
    /// it. That is the whole point: the user's 55% stays recorded, so it comes back
    /// untouched if this Mac's firmware ever regains a mechanism that can honour it —
    /// while the knob and the label above it agree with the value actually in force,
    /// which is what the disclosures beside them name.
    public static func displayedLimit(configured: Int, for backend: ChargeBackend?) -> Int {
        min(max(configured, lowestSelectable(for: backend)), highest)
    }
}
