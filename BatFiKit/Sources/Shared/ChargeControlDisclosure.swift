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
    /// No usable mechanism at all — BatFi cannot control charging on this firmware.
    case chargingControlUnavailable

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

    /// Pausing charging outright cannot engage: Apple's limit holds charge at a
    /// percentage and bottoms out at 80%, and there is no inhibit key left to write. This
    /// is why hot-battery protection and pause-on-sleep do nothing under
    /// `.systemChargeLimit`, and it cannot be fixed — only disclosed.
    ///
    /// `forceDischargeStillAvailable` is carried rather than implied, deliberately.
    /// Force discharge is probed from its own key (`CHIE` outlives `CHTE`), so "Run on
    /// Battery" can still work on a machine that has lost charge limiting — and sweeping
    /// it into this case would tell a user that a feature which works is broken.
    case pausingChargingUnavailable(forceDischargeStillAvailable: Bool)
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
        let forceDischarge: Bool = diagnostics?.forceDischargeAvailable ?? false

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
    /// — which is the thing `.systemChargeLimit` cannot do. Gated on `manageCharging`
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

        case .unsupported:
            return [.chargingControlUnavailable]

        case .systemChargeLimit:
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
                    .pausingChargingUnavailable(forceDischargeStillAvailable: forceDischargeAvailable)
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
        case .chte, .legacyCH0BC:
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
    /// Exhaustive over `ChargeBackend`, with `.unsupported` deliberately *not* constrained
    /// even though `honoursLimitsBelow80` is false for it. The constraint exists to stop
    /// the user choosing a value that would be silently raised to something else — and
    /// under `.unsupported` nothing is applied at all, so raising the floor to 80% would
    /// imply 80% is in force when nothing is. That Mac is told the truth by
    /// `.chargingControlUnavailable` instead.
    public static func lowestSelectable(for backend: ChargeBackend?) -> Int {
        guard let backend else { return lowest }
        switch backend {
        case .chte, .legacyCH0BC: return lowest
        case .systemChargeLimit: return systemChargeLimitLowest
        case .unsupported: return lowest
        }
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
