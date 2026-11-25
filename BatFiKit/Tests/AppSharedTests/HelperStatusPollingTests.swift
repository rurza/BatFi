//
//  HelperStatusPollingTests.swift
//  BatFi
//
//  How often the app may ask `SMAppService` for the helper's status. Every read makes
//  `backgroundtaskmanagementd` re-validate the app bundle, which re-reads the whole main
//  executable from disk — a customer measured 27 GB read since boot from a 1.5s poll that
//  ran for the app's whole life. The fast cadence is for the states that are waiting on a
//  status change; a helper that works is not one of them.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct HelperStatusPollingTests {
    private static let conflict = HelperOwnershipConflict(
        kind: .otherBundle,
        runningExecutablePath: "/Users/adam/Downloads/BatFi.app/Contents/MacOS/BatFiHelper",
        expectedExecutablePath: "/Applications/BatFi.app/Contents/MacOS/BatFiHelper",
        runningVersion: "99999",
        owningAppPath: "/Users/adam/Downloads/BatFi.app"
    )

    /// Every state the health policy can be in other than working. Each of them is either
    /// counting readings towards a verdict — the absence and pending-approval budgets are
    /// sized to the fast cadence — or waiting for a repair only a status change reveals.
    static let unsettledHealth: [HelperHealth] = [
        .unknown,
        .degraded(.notRegistered),
        .degraded(.requiresApproval),
        .degraded(.registeredButUnreachable),
        .degraded(.staleRegistrationNeedsUserReset),
        .degraded(.installFailed("Operation not permitted")),
        .degraded(.foreignHelper(conflict)),
    ]

    @Test("A healthy helper is read rarely, as a backstop only")
    func healthyHelperIsReadRarely() {
        let interval = HelperStatusPolling.interval(for: .healthy)

        #expect(interval >= .seconds(5 * 60))
        #expect(interval <= .seconds(10 * 60))
    }

    @Test("Every state that waits on a status change keeps the fast cadence", arguments: unsettledHealth)
    func unsettledHealthIsReadFast(_ health: HelperHealth) {
        #expect(HelperStatusPolling.interval(for: health) == HelperStatusPolling.unsettledInterval)
    }

    /// The budgets in `HelperHealthPolicy` count readings and were sized against a 1.5s
    /// tick: about three seconds of agreement before reporting an absence, about fifteen
    /// before interrupting a pending approval. A slower unsettled cadence would stretch both.
    @Test("The fast cadence is the one the policy's reading budgets were sized against")
    func unsettledIntervalMatchesTheBudgets() {
        #expect(HelperStatusPolling.unsettledInterval == .milliseconds(1500))
    }

    /// The case that matters: the helper stops working while the app is sitting out a long
    /// healthy wait. Waiting the rest of ten minutes would leave every budget stalled and a
    /// repair the user makes in Login Items unnoticed.
    @Test("Losing a healthy helper cuts the long wait short", arguments: unsettledHealth)
    func losingHealthEndsTheWait(_ health: HelperHealth) {
        #expect(HelperStatusPolling.endsWaitEarly(
            waiting: HelperStatusPolling.interval(for: .healthy),
            health: health
        ))
    }

    /// The other direction. A short wait that is already running finishes on its own a
    /// moment later, and reading early there would add a reading to a budget that counts
    /// them — corroborating an absence in half the time it is meant to take.
    @Test("A change between unsettled states, or into healthy, does not cut the wait short")
    func otherChangesDoNotEndTheWait() {
        for health in Self.unsettledHealth + [.healthy] {
            #expect(!HelperStatusPolling.endsWaitEarly(
                waiting: HelperStatusPolling.unsettledInterval,
                health: health
            ))
        }
        #expect(!HelperStatusPolling.endsWaitEarly(
            waiting: HelperStatusPolling.interval(for: .healthy),
            health: .healthy
        ))
    }
}
