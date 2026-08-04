//
//  AppliedChargeLimitTests.swift
//  BatFi
//
//  Three decisions that hang off "has anything actually changed?", and one that decides
//  whether a read of the system charge limit may be trusted as the user's own. All four
//  used to be inequality checks, unguarded reads or unbounded logging, and all four
//  misbehaved in the steady state of the `.systemChargeLimit` backend rather than at its
//  edges — which is why the steady state is what they are pinned against here.
//

import Foundation
import Testing

@testable import Shared

@Suite struct AppliedChargeLimitTests {
    // MARK: - needsWrite

    /// Nothing in force yet, so the first request always writes.
    @Test func theFirstRequestAlwaysNeedsWriting() {
        let outcome = AppliedChargeLimit(requested: 55, applied: 80)
        #expect(AppliedChargeLimit.needsWrite(outcome, inForce: nil))
    }

    /// The point of the guard: `setMCLLimit:` mutates a control the user can see, and the
    /// call that reaches it runs on every status update, roughly once a minute forever.
    @Test func repeatingTheSameRequestDoesNotWriteAgain() {
        let outcome = AppliedChargeLimit(requested: 55, applied: 80)
        #expect(AppliedChargeLimit.needsWrite(outcome, inForce: outcome) == false)
    }

    /// The user moving the slider has to reach the hardware even when the value the
    /// mechanism can express does not change — otherwise the record and reality diverge.
    @Test func aChangedRequestNeedsWritingEvenWhenItResolvesTheSame() {
        let inForce = AppliedChargeLimit(requested: 55, applied: 80)
        let outcome = AppliedChargeLimit(requested: 70, applied: 80)
        #expect(AppliedChargeLimit.needsWrite(outcome, inForce: inForce))
    }

    @Test func aChangedResolutionNeedsWriting() {
        let inForce = AppliedChargeLimit(requested: 85, applied: 85)
        let outcome = AppliedChargeLimit(requested: 85, applied: 90)
        #expect(AppliedChargeLimit.needsWrite(outcome, inForce: inForce))
    }

    /// How the guard is kept from wedging: everything that ends BatFi's ownership of the
    /// limit — a release, a restore, a dropped backend resolution — clears what is in
    /// force, and a cleared record always writes.
    @Test func clearingWhatIsInForceAlwaysWritesAgain() {
        let outcome = AppliedChargeLimit(requested: 80, applied: 80)
        #expect(AppliedChargeLimit.needsWrite(outcome, inForce: outcome) == false)
        #expect(AppliedChargeLimit.needsWrite(outcome, inForce: nil))
    }

    // MARK: - shouldReport

    /// A request the mechanism honoured exactly is not news. This is every SMC backend,
    /// on every status update.
    @Test func anHonouredRequestIsNeverReported() {
        let outcome = AppliedChargeLimit(requested: 80, applied: 80)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: nil) == false)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: outcome) == false)
    }

    @Test func aRaisedLimitIsReportedTheFirstTime() {
        let outcome = AppliedChargeLimit(requested: 55, applied: 80)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: nil))
    }

    /// The finding this replaces: the slider is 50…90 and Apple's limit cannot go below
    /// 80, so for most users the mismatch is the permanent steady state of the backend.
    /// Reporting it as an inequality meant a notice and a Sentry breadcrumb every pass.
    @Test func anUnchangedMismatchIsReportedOnlyOnce() {
        let outcome = AppliedChargeLimit(requested: 55, applied: 80)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: outcome) == false)
        for requested in [50, 55, 60, 65, 70, 75] {
            let steady = AppliedChargeLimit(requested: requested, applied: 80)
            #expect(AppliedChargeLimit.shouldReport(steady, lastReported: steady) == false)
        }
    }

    /// "Run on Battery" sets a temp limit of 0, which resolves to 80 on every pass while
    /// discharging — the loudest case of all under the old inequality check.
    @Test func theRunOnBatteryOverrideIsReportedOnlyOnce() {
        let outcome = AppliedChargeLimit(requested: 0, applied: 80)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: nil))
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: outcome) == false)
    }

    /// A genuinely new mismatch still gets through.
    @Test func aDifferentMismatchIsReported() {
        let last = AppliedChargeLimit(requested: 55, applied: 80)
        #expect(AppliedChargeLimit.shouldReport(AppliedChargeLimit(requested: 82, applied: 85), lastReported: last))
    }

    /// Clearing the memory — what `disengage()` does — makes the next episode report again.
    @Test func clearingTheMemoryReportsOnceMore() {
        let outcome = AppliedChargeLimit(requested: 55, applied: 80)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: outcome) == false)
        #expect(AppliedChargeLimit.shouldReport(outcome, lastReported: nil))
    }

    // MARK: - wasRaised

    @Test func onlyAnAppliedValueAboveTheRequestCountsAsRaised() {
        #expect(AppliedChargeLimit(requested: 55, applied: 80).wasRaised)
        #expect(AppliedChargeLimit(requested: 80, applied: 80).wasRaised == false)
        // Clamping down to the highest expressible value is not a raise.
        #expect(AppliedChargeLimit(requested: 200, applied: 100).wasRaised == false)
    }

    // MARK: - SystemLimitSnapshot

    /// The normal case: no override held here, and PowerUI's clear has been invoked, so
    /// nothing BatFi wrote can still be standing in front of the read.
    @Test func aReadIsTrustworthyWithNoOverrideAndAnInvokedClear() {
        #expect(SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: false,
            canWriteOverride: true,
            overrideRetired: true
        ))
    }

    /// This process is holding an override, so the limit reads back as BatFi's 100. The
    /// dominant condition: it refuses whatever the build can or cannot do.
    @Test func anOverrideThisProcessHoldsBlocksTheRead() {
        #expect(SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: true,
            canWriteOverride: true,
            overrideRetired: true
        ) == false)
        #expect(SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: true,
            canWriteOverride: false,
            overrideRetired: true
        ) == false)
    }

    /// The scenario that makes this worth a guard at all: an override outlives the process
    /// that set it, so a BatFi that crashed while holding one leaves the limit reading 100.
    /// A fresh process has no memory of it — `hasActiveOverride` is false — and only an
    /// actually-invoked `clearMCLOverride` can retire it. Without that, refusing is the
    /// only safe answer: a missing snapshot is retried, a wrong one is restored on quit
    /// and the user's saved limit is gone.
    @Test func aReadIsRefusedWhileAnUnretiredBatFiOverrideIsPossible() {
        #expect(SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: false,
            canWriteOverride: true,
            overrideRetired: false
        ) == false)
    }

    /// The narrowing. On a build that exposes no override selector, BatFi has never been
    /// able to write an override here — in this process or in one that died holding one —
    /// so the read is the user's value by construction and there is nothing for a clear to
    /// retire. Refusing anyway would protect against nothing and would leave
    /// `.systemChargeLimit` unable to apply any limit at all for the life of the process.
    @Test func aReadIsTrustworthyWhenBatFiCannotWriteAnOverrideAtAll() {
        #expect(SystemLimitSnapshot.readIsTrustworthy(
            hasActiveOverride: false,
            canWriteOverride: false,
            overrideRetired: false
        ))
    }

    // MARK: - ChargeLimitFailure

    @Test func theFirstFailureIsReported() {
        let failure = ChargeLimitFailure(requested: 80, reason: "snapshotUnavailable")
        #expect(ChargeLimitFailure.shouldReport(failure, lastReported: nil))
    }

    /// The finding: the reasons a limit cannot be applied — the wrong firmware, a missing
    /// PowerUI selector, no trustworthy snapshot — last as long as the process, while the
    /// call runs on every status update. Repeating it is a warning and a burnt Sentry
    /// breadcrumb a minute, forever.
    @Test func anUnchangedFailureIsReportedOnlyOnce() {
        let failure = ChargeLimitFailure(requested: 80, reason: "snapshotUnavailable")
        #expect(ChargeLimitFailure.shouldReport(failure, lastReported: failure) == false)
    }

    @Test func aDifferentReasonForTheSameLimitIsReported() {
        let last = ChargeLimitFailure(requested: 80, reason: "snapshotUnavailable")
        let next = ChargeLimitFailure(requested: 80, reason: "frameworkUnavailable")
        #expect(ChargeLimitFailure.shouldReport(next, lastReported: last))
    }

    /// The user moved the slider and it still fails — worth saying, because which value
    /// was refused is half the diagnosis.
    @Test func theSameReasonForADifferentLimitIsReported() {
        let last = ChargeLimitFailure(requested: 80, reason: "snapshotUnavailable")
        let next = ChargeLimitFailure(requested: 90, reason: "snapshotUnavailable")
        #expect(ChargeLimitFailure.shouldReport(next, lastReported: last))
    }

    /// Clearing the memory — what a success and what `disengage()` both do — makes the
    /// same failure an event again, so a failure that returns after the limit worked is
    /// not swallowed.
    @Test func clearingTheFailureMemoryReportsOnceMore() {
        let failure = ChargeLimitFailure(requested: 80, reason: "snapshotUnavailable")
        #expect(ChargeLimitFailure.shouldReport(failure, lastReported: failure) == false)
        #expect(ChargeLimitFailure.shouldReport(failure, lastReported: nil))
    }
}
