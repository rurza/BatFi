//
//  AppliedChargeLimit.swift
//
//
//  What a charge-limit request resolved to, what it does when it resolves to nothing at
//  all, and the decisions that hang off both.
//

import Foundation

/// The outcome of one charge-limit request: what was asked for, and what the mechanism
/// could actually put in force. The two differ under Apple's Manual Charge Limit, which
/// accepts only a short list of values and cannot go below 80%.
///
/// Lives here rather than in the helper so the decisions below — "does this need
/// writing again?" and "is this worth reporting?" — are pure, and testable without the
/// SMC or the PowerUI private framework.
public struct AppliedChargeLimit: Equatable, Sendable {
    public let requested: Int
    public let applied: Int

    public init(requested: Int, applied: Int) {
        self.requested = requested
        self.applied = applied
    }

    /// Whether the mechanism had to charge past the point the user asked for.
    public var wasRaised: Bool { applied > requested }

    /// Whether this outcome still has to be written, given what is already in force.
    ///
    /// `inForce` is only ever non-`nil` after a **successful** write, so a `false` here
    /// means the exact same request already resolved to the exact same value and the
    /// mechanism already holds it. Anything that ends BatFi's ownership of the limit —
    /// a release, a restore, a change of backend — clears `inForce`, so the guard can
    /// never keep BatFi from re-establishing a limit it no longer holds.
    public static func needsWrite(_ outcome: AppliedChargeLimit, inForce: AppliedChargeLimit?) -> Bool {
        inForce != outcome
    }

    /// Whether this outcome is worth a log line and a breadcrumb.
    ///
    /// On *change*, not on inequality. A user whose limit is below 80% sits permanently
    /// in the mismatched state — that is the steady state of the backend, not an event —
    /// and reporting inequality would emit a notice and a Sentry breadcrumb on every
    /// status update, forever, on exactly the machines whose bug reports matter most.
    public static func shouldReport(_ outcome: AppliedChargeLimit, lastReported: AppliedChargeLimit?) -> Bool {
        guard outcome.applied != outcome.requested else { return false }
        return lastReported != outcome
    }
}

/// When a read of the system charge limit may be recorded as *the user's own* value.
///
/// The hazard this exists for: BatFi's temporary MCL override makes the limit read back
/// as BatFi's value rather than the user's, and an override outlives the process that
/// set it. Snapshotting under one means BatFi restores its own number on quit and the
/// user's saved limit is gone for good.
///
/// ## What this rule covers, exactly
///
/// **MCL overrides only** — the `temporarilyOverrideMCLTargetSoC:` write. It does *not*
/// cover BatFi's other write of the same user-visible value, `setMCLLimit:` on the adopt
/// path, which is the write `.systemChargeLimit` machines actually make and which, unlike
/// an override, never expires. A process that adopted 80% and then died without restoring
/// leaves 80% in force, and the next process — writing no override, so trusted by the
/// rule below — records that 80% as the user's own value.
///
/// That is sound **only because the snapshot does not outlive the process that took it**.
/// The crash already lost the user's real value irrecoverably (nothing durable recorded
/// it), and the new process restoring 80% later writes back exactly what is already in
/// force, so trusting the read loses nothing further.
///
/// **If the snapshot is ever persisted across processes, that argument fails and this rule
/// must be widened to cover adopts** — a persisted snapshot would have the user's real
/// value to lose, and the new process would overwrite it with BatFi's. Widening it needs a
/// durable "an adopt is outstanding" marker, i.e. the same cross-process state that
/// persisting the resolved backend needs; do not persist one without the other.
public enum SystemLimitSnapshot {
    /// - Parameters:
    ///   - hasUnretiredOverride: whether *this* process has written an override that has
    ///     not been verifiably retired since. Not "is the renewal task running": a clear
    ///     that found no selector to call stops the renewals but retires nothing, and the
    ///     override stands until its own expiry. Only a clear that actually ran ends this.
    ///   - canWriteOverride: whether this build of PowerUI exposes the selector BatFi's
    ///     override is written with. When it does not, BatFi has never been able to put
    ///     an override in front of the read — not in this process and not in any earlier
    ///     one — so there is nothing for a clear to retire and the read is the user's
    ///     value by construction.
    ///   - backendWritesOverrides: whether BatFi writes an override under the backend in
    ///     force on this machine — `ChargeBackend.writesMCLOverride`. The second, weaker
    ///     way of establishing the same fact as `canWriteOverride`: BatFi may be *able* to
    ///     write an override and still never do so here, because only the SMC backends
    ///     write one and the backend follows the firmware, which no BatFi process on this
    ///     Mac can have seen differently.
    ///   - overrideRetired: whether PowerUI's clear selector has actually been invoked
    ///     since the process started. That is the only thing that can retire an override
    ///     left behind by an earlier BatFi that crashed while holding one; without it,
    ///     a read cannot be told apart from that earlier process's write.
    ///
    /// The rule is "no BatFi *override* can be standing in front of this read" — see the
    /// scope note on the type for the one BatFi write it deliberately does not cover — and
    /// it is no broader than that. Requiring an invoked clear unconditionally would
    /// refuse forever on a build that exposes no clear selector — and PowerUI on shipping
    /// macOS exposes `temporarilyOverrideMCLTargetSoC:error:` with no clear counterpart of
    /// any spelling, so that is not a hypothetical build but the normal one. On a machine
    /// that resolves `.systemChargeLimit` the refusal then protects against nothing and
    /// costs the entire feature: no override is ever written there, so no read can be
    /// poisoned, yet every limit would be refused for the life of the process.
    ///
    /// Refusing stays the answer wherever a BatFi write is genuinely possible — chiefly
    /// the mixed machine that resolves an SMC backend *and* has a Manual Charge Limit,
    /// where BatFi really does write an override and really cannot clear one. A missing
    /// snapshot is retried on the next pass; a wrong one is written into a setting the
    /// user can see and cannot get back.
    public static func readIsTrustworthy(
        hasUnretiredOverride: Bool,
        canWriteOverride: Bool,
        backendWritesOverrides: Bool,
        overrideRetired: Bool
    ) -> Bool {
        guard !hasUnretiredOverride else { return false }
        // Two independent ways for a BatFi override to be impossible here: the selector to
        // write one does not exist, or the backend in force never asks for one. Either is
        // enough, and neither depends on a clear that may not exist. Neither implies the
        // other, either — they are properties of different things (this build of PowerUI,
        // and this machine's firmware). The combinations measured in the field are both
        // `canWriteOverride`: shipping macOS on SMC firmware is `can && writes`, macOS 27
        // firmware is `can && !writes`. A build exposing no override selector has never
        // been seen, which is why `canWriteOverride` alone cannot carry this decision.
        guard canWriteOverride, backendWritesOverrides else { return true }
        return overrideRetired
    }
}

/// A charge-limit request the mechanism could not put in force at all.
///
/// Separate from `AppliedChargeLimit` because there is no applied value to speak of, but
/// it needs the same treatment for the same reason: nearly everything that makes this
/// fail is fixed for the life of the process — a PowerUI selector this build does not
/// expose, no trustworthy record of the user's own value, the wrong firmware — so the
/// failure is a *state*, while the call site runs on every status update.
public struct ChargeLimitFailure: Equatable, Sendable {
    public let requested: Int

    /// A stable description of what went wrong, used only to tell one failure from
    /// another. Two passes that fail the same way produce the same string.
    public let reason: String

    public init(requested: Int, reason: String) {
        self.requested = requested
        self.reason = reason
    }

    /// Whether this failure is worth a log line and a breadcrumb: only when the failure
    /// state changed. `lastReported` is cleared by a success and by disengaging, so a
    /// failure that returns after the limit worked is an event again and is reported.
    public static func shouldReport(_ failure: ChargeLimitFailure, lastReported: ChargeLimitFailure?) -> Bool {
        lastReported != failure
    }
}
