//
//  ChargeLimitReassertionTests.swift
//  BatFi
//
//  Captured live on macOS 27.0 (26A5416b) while the limit was dragged from 65% to 70%:
//
//      15:48:02.679  Charge limit request for 65% went missing while waiting; writing it again
//      15:48:02.929  Charge limit request for 70% went missing while waiting; writing it again
//      15:48:03.229  Charge limit request for 65% went missing while waiting; writing it again
//      …  ~2 rounds a second, each, for five seconds …
//      15:48:07.178  Charge limit 70% adopted by powerd
//      15:48:16.827  Charge limit 65% adopted by powerd     ← the superseded request won
//      15:48:26.779  Charge limit 70% adopted by powerd     ← a later status pass undid it
//
//  Two requests, each reading the other's write as its own going missing, each putting its
//  own back. `powerdAdopts` polls across an `await`, and actors are reentrant, so the two
//  interleave rather than queue. The stale one is entitled to fight for its full 45-second
//  budget, and nothing decides in favour of the newer request — here it lost, and powerd
//  spent nine seconds enforcing a limit the user had already moved away from.
//
//  A stale request that wins by a *higher* value is the same bug with the consequence
//  reversed: the Mac charges past the limit the user just set, while BatFi records the new
//  one as applied.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargeLimitReassertionTests {
    private let mine: ChargeLimitRequestID = 7
    private let newer: ChargeLimitRequestID = 8

    // MARK: - The bug

    /// The line the log above is full of. A superseded request must not write, however
    /// certain it is that its own value has gone missing — the value that replaced it is
    /// the newer request's, and rewriting is what starts the fight.
    @Test func aSupersededRequestDoesNotRewriteWhenItsValueIsGone() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 65,
                requestID: mine,
                latestRequestID: newer,
                enforcedLimit: nil,
                writtenRequest: 70
            ) == .superseded
        )
    }

    /// And it does not get to declare victory either. powerd adopting 65 nine seconds after
    /// adopting 70 is the moment the stale request would otherwise report success and have
    /// its value recorded as the one in force.
    @Test func aSupersededRequestDoesNotClaimAdoption() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 65,
                requestID: mine,
                latestRequestID: newer,
                enforcedLimit: 65,
                writtenRequest: 65
            ) == .superseded
        )
    }

    /// Being superseded outlives the request that superseded it. The newer request finishes
    /// and clears itself; the older one must stay dead rather than find the field empty and
    /// resume. Identity is compared, never "is anything in flight".
    @Test func aSupersededRequestStaysDeadAfterTheNewerOneFinishes() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 65,
                requestID: mine,
                latestRequestID: newer,
                enforcedLimit: 70,
                writtenRequest: nil
            ) == .superseded
        )
    }

    // MARK: - The ordinary life of a request that is still the newest

    @Test func theNewestRequestRewritesWhatWentMissing() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 70,
                requestID: newer,
                latestRequestID: newer,
                enforcedLimit: nil,
                writtenRequest: nil
            ) == .rewriteRequest
        )
    }

    @Test func aRequestPowerdIsEnforcingIsAdopted() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 70,
                requestID: newer,
                latestRequestID: newer,
                enforcedLimit: 70,
                writtenRequest: 70
            ) == .adopted
        )
    }

    /// Adoption takes tens of seconds and the preference is still there. Waiting is the
    /// whole point of the loop.
    @Test func aWrittenRequestThatIsNotYetEnforcedWaits() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 70,
                requestID: newer,
                latestRequestID: newer,
                enforcedLimit: 60,
                writtenRequest: 70
            ) == .keepWaiting
        )
    }

    /// powerd holding some other limit is not this request's business — it is what the
    /// request is trying to change. Only the preference going missing prompts a rewrite.
    @Test func anotherLimitInForceDoesNotByItselfPromptARewrite() {
        #expect(
            ChargeLimitReassertion.step(
                requested: 70,
                requestID: newer,
                latestRequestID: newer,
                enforcedLimit: 100,
                writtenRequest: 70
            ) == .keepWaiting
        )
    }
}
