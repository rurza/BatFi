//
//  ChargeRangeCallTests.swift
//  BatFi
//
//  Which helper call carries a sailing band. A helper too old to know the two-value
//  call drops the message rather than failing it, so the choice has to be made before
//  asking — from the running helper's version — and a helper that cannot be read is
//  asked the way every helper has always been asked.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargeRangeCallTests {
    @Test func theFirstHelperThatKnowsTheCallIsAsked() {
        #expect(ChargeRangeCall.helperServesChargeRange(version: "4.2.0"))
    }

    @Test func laterHelpersAreAsked() {
        #expect(ChargeRangeCall.helperServesChargeRange(version: "4.2.1"))
        #expect(ChargeRangeCall.helperServesChargeRange(version: "4.10.0"))
        #expect(ChargeRangeCall.helperServesChargeRange(version: "5.0"))
        #expect(ChargeRangeCall.helperServesChargeRange(version: "5"))
    }

    @Test func helpersThatShippedBeforeTheCallAreNotAsked() {
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "4.1.0"))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "4.0.3"))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "3.2.0"))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "4.1.99"))
    }

    /// Unknown is the old call: it is the one every helper serves, and the worst it does
    /// is put today's band in force instead of the wider one.
    @Test func anUnreadableVersionIsNotAsked() {
        #expect(!ChargeRangeCall.helperServesChargeRange(version: nil))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: ""))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "4.2.0-beta"))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "four"))
    }

    @Test func numericComponentsAreComparedAsNumbersNotText() {
        // "4.10.0" < "4.2.0" as text; as a version it is later.
        #expect(ChargeRangeCall.helperServesChargeRange(version: "4.10"))
        #expect(!ChargeRangeCall.helperServesChargeRange(version: "4.1.10"))
    }
}

/// Which call to make now, given what is known about the running helper: its version, read
/// once per process, and whether it already refused this exact range.
///
/// A refusal is remembered so a helper that keeps failing the range call is not asked
/// twice on every charging pass — once for the range, once for the fallback. A dropped
/// connection or a watchdog timeout is not a refusal: the helper never answered, and the
/// error goes up the way today's call's errors do.
@Suite struct ChargeRangeCallPolicyTests {
    private let pid: pid_t = 501

    private func capableHelper() -> ChargeRangeCallPolicy {
        var policy = ChargeRangeCallPolicy()
        policy.recordVersion("4.2.0", of: pid)
        return policy
    }

    @Test func anOlderHelperGetsTheOneValueCall() {
        var policy = ChargeRangeCallPolicy()
        policy.recordVersion("4.1.0", of: pid)
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call == .limitOnly)
    }

    @Test func aHelperWhoseVersionIsUnreadableGetsTheOneValueCall() {
        var policy = ChargeRangeCallPolicy()
        policy.recordVersion(nil, of: pid)
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call == .limitOnly)
    }

    @Test func aHelperNotYetReadGetsTheOneValueCall() {
        var policy = ChargeRangeCallPolicy()
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call == .limitOnly)
        let call2 = policy.call(pid: nil, limit: 80, resumeLevel: 70)
        #expect(call2 == .limitOnly)
    }

    @Test func aCapableHelperWithNoRefusalGetsTheRangeCall() {
        var policy = capableHelper()
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call == .range)
    }

    /// Once per process, including the "unknown" answer: reading it again costs a code
    /// signature check and two log lines on every pass, and a new process is a new pid.
    @Test func theVersionIsReadOncePerProcessEvenWhenUnreadable() {
        var policy = ChargeRangeCallPolicy()
        #expect(policy.needsVersion(of: pid))
        policy.recordVersion(nil, of: pid)
        #expect(!policy.needsVersion(of: pid))
        #expect(policy.needsVersion(of: pid + 1))
    }

    @Test func aRefusalFallsBackAndIsNotAskedAgainForTheSameRange() {
        var policy = capableHelper()
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call == .range)
        let fallsBack = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        #expect(fallsBack)
        let call2 = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call2 == .limitOnly)
        let call3 = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call3 == .limitOnly)
    }

    @Test func aNewHelperProcessIsAskedAgain() {
        var policy = capableHelper()
        _ = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        policy.recordVersion("4.2.0", of: pid + 1)
        let call = policy.call(pid: pid + 1, limit: 80, resumeLevel: 70)
        #expect(call == .range)
    }

    @Test func aNewLimitIsAskedAgain() {
        var policy = capableHelper()
        _ = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        let call = policy.call(pid: pid, limit: 85, resumeLevel: 70)
        #expect(call == .range)
    }

    @Test func aNewResumeLevelIsAskedAgain() {
        var policy = capableHelper()
        _ = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 65)
        #expect(call == .range)
    }

    /// "Until the range changes" means the refusal is over once it does: coming back to
    /// the refused range later asks again rather than staying on the one-value call.
    @Test func aRefusalIsForgottenOnceTheRangeChanges() {
        var policy = capableHelper()
        _ = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 65)
        #expect(call == .range)
        let call2 = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call2 == .range)
    }

    // MARK: - Asking ahead which call would go out

    /// Sailing under `.firmwareRange` has to know before it asks whether the two-value call
    /// would go out: with only the one-value call the app keeps today's behaviour.
    @Test func theCallAheadFollowsTheVersion() {
        var older = ChargeRangeCallPolicy()
        older.recordVersion("4.1.0", of: pid)
        #expect(older.wouldCall(pid: pid, limit: 80, resumeLevel: 70) == .limitOnly)
        #expect(ChargeRangeCallPolicy().wouldCall(pid: pid, limit: 80, resumeLevel: 70) == .limitOnly)
        #expect(capableHelper().wouldCall(pid: nil, limit: 80, resumeLevel: 70) == .limitOnly)
        #expect(capableHelper().wouldCall(pid: pid, limit: 80, resumeLevel: 70) == .range)
    }

    @Test func theCallAheadFollowsARememberedRefusal() {
        var policy = capableHelper()
        _ = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        #expect(policy.wouldCall(pid: pid, limit: 80, resumeLevel: 70) == .limitOnly)
        #expect(policy.wouldCall(pid: pid, limit: 76, resumeLevel: 70) == .range)
    }

    /// Asking ahead is only a question: it does not forget a refusal the way a call for
    /// another range does.
    @Test func askingAheadForgetsNothing() {
        var policy = capableHelper()
        _ = policy.shouldFallBack(after: .helperRefused, pid: pid, limit: 80, resumeLevel: 70)
        _ = policy.wouldCall(pid: pid, limit: 76, resumeLevel: 70)
        #expect(policy.call(pid: pid, limit: 80, resumeLevel: 70) == .limitOnly)
    }

    @Test func aLostConnectionDoesNotFallBackOrRecordARefusal() {
        var policy = capableHelper()
        let fallsBack = policy.shouldFallBack(after: .noAnswer, pid: pid, limit: 80, resumeLevel: 70)
        #expect(!fallsBack)
        let call = policy.call(pid: pid, limit: 80, resumeLevel: 70)
        #expect(call == .range)
    }
}
