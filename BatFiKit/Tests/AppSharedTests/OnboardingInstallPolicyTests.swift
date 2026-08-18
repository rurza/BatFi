//
//  OnboardingInstallPolicyTests.swift
//  BatFi
//
//  The observed bug, from a real session on 2026-08-17:
//
//      20:13:24  "Installing daemon..."
//      20:13:24  register() → SMAppServiceErrorDomain Code=1 "Operation not permitted"
//      20:13:25  status requiresApproval
//      20:13:25 → onwards   nothing. Ever.
//
//  The pane's Install button span for the rest of the session. `.requiresApproval` matched no
//  arm of the status loop, so the loop never ended, `isLoading` was never cleared, and the one
//  alert the loop could produce fired on a `counter == 20` equality that cannot match twice.
//  Meanwhile the app already owned the correct sentence — `helperNeedsApproval`, "macOS has
//  registered BatFi's helper but is waiting for you to allow it" — and could not reach it,
//  because guidance is suppressed while onboarding is up.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct OnboardingInstallPolicyTests {
    /// The bug, at its smallest. macOS has already spoken; there is nothing to wait for.
    @Test func requiresApprovalIsReportedAtOnce() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .requiresApproval,
                registrationError: nil,
                tick: 0
            ) == .needsApproval
        )
    }

    /// The status stream repeats every 1.5s and the pane re-reads it on every tick. A verdict
    /// that only holds on one tick is the `counter == 20` defect this replaces: the user
    /// dismisses the alert, the equality never matches again, and the pane goes quiet for the
    /// rest of the session.
    @Test func requiresApprovalKeepsBeingReportedOnEveryLaterTick() {
        for tick in [1, 19, 20, 21, 500] {
            #expect(
                OnboardingInstallPolicy.progress(
                    status: .requiresApproval,
                    registrationError: nil,
                    tick: tick
                ) == .needsApproval,
                "tick \(tick) still needs approval — nothing has changed the record"
            )
        }
    }

    /// Both were true at 20:13:24: `register()` threw "Operation not permitted" *and* the
    /// record landed in `.requiresApproval` a second later. Neither cancels the other, and
    /// which one to say depends on whether the refusal sticks.
    ///
    /// "Installation failed, try again" invites the user to mash Install, and re-registering
    /// in a loop is the behaviour most plausibly associated with wedging the very record the
    /// pane is waiting on. So inside the grace the pane says the ordinary thing.
    @Test func aRefusalInsideTheGraceIsStillReportedAsPendingApproval() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .requiresApproval,
                registrationError: "Operation not permitted",
                tick: OnboardingInstallPolicy.failureGraceTicks - 1
            ) == .needsApproval
        )
    }

    /// MEASURED 2026-08-17/18 on this Mac, and the reason this case exists at all.
    ///
    /// `SMAppService.Status` has four values and macOS folds two different situations into
    /// `.requiresApproval`. `smd` showed the difference the enum throws away:
    ///
    ///     getEffectiveDisposition: disposition=[enabled, disallowed, notified], have LWCR=true
    ///     Found status: 2
    ///
    /// `enabled` is the user's switch — already on. `disallowed` is macOS refusing anyway,
    /// because the record's cached launch constraint no longer matches the bundle on disk.
    /// Telling that user to "turn it on" names a switch they have already turned on, which is
    /// exactly what happened: the approval alert was shown to someone already approved.
    ///
    /// Neither `register()` nor `unregister()` can clear it — both returned "Operation not
    /// permitted". Toggling the item off and on in System Settings did, immediately:
    ///
    ///     disposition=[enabled, allowed, notified]   →   helper spawned, health healthy
    ///
    /// The refusal is the signal, but only once it has outlived the grace. A lone EPERM is
    /// the ordinary transient refusal here — `helperInstallFailed` says so — and a transient
    /// one stops being true before the grace is up.
    @Test func aRefusalThatOutlivesTheGraceIsAWedgedRecord() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .requiresApproval,
                registrationError: "Operation not permitted",
                tick: OnboardingInstallPolicy.failureGraceTicks
            ) == .needsManualReset
        )
    }

    /// A registration macOS accepted is genuinely pending the user's consent, however long
    /// they take to give it. Nothing here should ever escalate to telling them to reset a
    /// record that is working exactly as intended.
    @Test func anAcceptedRegistrationNeverEscalatesToAManualReset() {
        for tick in [0, 20, 500, 5000] {
            #expect(
                OnboardingInstallPolicy.progress(
                    status: .requiresApproval,
                    registrationError: nil,
                    tick: tick
                ) == .needsApproval,
                "tick \(tick): macOS accepted the registration, so there is nothing wedged"
            )
        }
    }

    /// Kept from the behaviour this replaces. `SMAppService.status` answers from Background
    /// Task Management rather than from the daemon, and a refusal reported the instant it is
    /// asked for can be overtaken by a record that lands a tick later — which is exactly what
    /// happened at 20:13:25. Announcing the refusal immediately would have named a failure
    /// that had already stopped being the truth.
    @Test func aRefusedRegistrationIsNotAnnouncedImmediately() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .notRegistered,
                registrationError: "Operation not permitted",
                tick: 0
            ) == .waiting
        )
    }

    @Test func aRefusedRegistrationIsAnnouncedOnceTheGraceHasPassed() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .notRegistered,
                registrationError: "Operation not permitted",
                tick: OnboardingInstallPolicy.failureGraceTicks
            ) == .failed("Operation not permitted")
        )
    }

    /// Same defect as the approval case: a verdict pinned to one exact tick disappears on the
    /// next one.
    @Test func aRefusedRegistrationStaysAnnouncedAfterTheGrace() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .notRegistered,
                registrationError: "Operation not permitted",
                tick: OnboardingInstallPolicy.failureGraceTicks + 1
            ) == .failed("Operation not permitted")
        )
    }

    /// Nothing was refused — the install simply has not landed yet. The loop's own
    /// install-once arm owns this, and there is nothing to tell the user.
    @Test func anAbsentRecordWithNoRefusalJustWaits() {
        for tick in [0, 20, 100] {
            #expect(
                OnboardingInstallPolicy.progress(
                    status: .notRegistered,
                    registrationError: nil,
                    tick: tick
                ) == .waiting,
                "tick \(tick): macOS has not refused anything"
            )
        }
    }

    /// `.enabled` is not this policy's business. It means a record exists, which is not the
    /// same as a helper that answers — the ping and ownership checks in the loop settle it,
    /// and they need I/O this type deliberately cannot do.
    @Test func anEnabledRecordIsLeftToThePingPath() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .enabled,
                registrationError: "Operation not permitted",
                tick: 99
            ) == .waiting
        )
    }

    /// `.notFound` is the same absence as `.notRegistered` — a record that named a bundle
    /// which is no longer there. It is not a refusal, so it says nothing on its own.
    @Test func anUnfindableRecordIsTreatedAsTheSameAbsence() {
        #expect(
            OnboardingInstallPolicy.progress(
                status: .notFound,
                registrationError: nil,
                tick: 50
            ) == .waiting
        )
    }

    /// The button. `.waiting` is the only progress that leaves it busy; the other two are
    /// both places where the app has stopped doing anything and is waiting on a person.
    @Test func onlyWaitingLeavesTheButtonBusy() {
        #expect(OnboardingInstallProgress.waiting.isBusy)
        #expect(!OnboardingInstallProgress.needsApproval.isBusy)
        #expect(!OnboardingInstallProgress.needsManualReset.isBusy)
        #expect(!OnboardingInstallProgress.failed("Operation not permitted").isBusy)
    }
}
