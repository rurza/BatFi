//
//  AppliedChargeLimit.swift
//
//
//  What a charge-limit request resolved to, and the decisions that hang off it.
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
public enum SystemLimitSnapshot {
    /// - Parameters:
    ///   - hasActiveOverride: whether *this* process is holding an override.
    ///   - canWriteOverride: whether this build of PowerUI exposes the selector BatFi's
    ///     override is written with. When it does not, BatFi has never been able to put
    ///     an override in front of the read — not in this process and not in any earlier
    ///     one — so there is nothing for a clear to retire and the read is the user's
    ///     value by construction.
    ///   - overrideRetired: whether PowerUI's clear selector has actually been invoked
    ///     since the process started. That is the only thing that can retire an override
    ///     left behind by an earlier BatFi that crashed while holding one; without it,
    ///     a read cannot be told apart from that earlier process's write.
    ///
    /// The rule is "nothing BatFi wrote can be standing in front of this read", and it is
    /// deliberately no broader than that. Requiring an invoked clear unconditionally would
    /// refuse forever on a build that exposes no clear selector — including one that
    /// exposes no *override* selector either, where the refusal protects against nothing
    /// and costs the whole feature. Refusing is the safe answer only where a BatFi write
    /// is genuinely possible: a missing snapshot is retried on the next pass, but a wrong
    /// one is written into a setting the user can see and cannot get back.
    public static func readIsTrustworthy(
        hasActiveOverride: Bool,
        canWriteOverride: Bool,
        overrideRetired: Bool
    ) -> Bool {
        guard !hasActiveOverride else { return false }
        guard canWriteOverride else { return true }
        return overrideRetired
    }
}
