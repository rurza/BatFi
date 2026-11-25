//
//  QuitExemptionsTests.swift
//  BatFi
//
//  Unit tests for the bookkeeping that leaves an app alone for a while after the
//  high-energy list asks it to quit, so that a slowed app is not too starved to answer.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct QuitExemptionsTests {
    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"

    @Test func nothingIsExemptAtFirst() {
        #expect(QuitExemptions().bundleIDs.isEmpty)
    }

    @Test func anAppAskedToQuitIsExempt() {
        var quits = QuitExemptions()

        let exemption = quits.exempt(slack)

        #expect(exemption.bundleID == slack)
        #expect(quits.bundleIDs == [slack])
    }

    @Test func theExemptionEndingLetsTheUsualRulesBack() {
        var quits = QuitExemptions()
        let exemption = quits.exempt(slack)
        _ = quits.exempt(safari)

        let ended = quits.ended(exemption)

        #expect(ended)
        #expect(quits.bundleIDs == [safari])
        // Ending it twice changes nothing more.
        let endedAgain = quits.ended(exemption)
        #expect(!endedAgain)
    }

    /// Asked again — the user pressed Quit a second time — the exemption starts over, and
    /// only the latest timer ends it.
    @Test func askingAgainRestartsTheExemption() {
        var quits = QuitExemptions()
        let first = quits.exempt(slack)
        let second = quits.exempt(slack)

        #expect(first != second)
        let firstEnded = quits.ended(first)
        #expect(!firstEnded)
        #expect(quits.bundleIDs == [slack])
        let secondEnded = quits.ended(second)
        #expect(secondEnded)
        #expect(quits.bundleIDs.isEmpty)
    }

    @Test func anExemptionLastsFifteenSecondsOnTheGivenClock() async {
        #expect(QuitExemptions.duration == .seconds(15))
        let clock = ManualClock()
        let timer = Task { await QuitExemptions.runOut(on: clock) }
        #expect(await eventually { clock.sleeperCount == 1 })

        clock.advance(by: .milliseconds(14_999))
        #expect(clock.sleeperCount == 1)

        clock.advance(by: .milliseconds(1))
        let ranOut = await timer.value
        #expect(ranOut)
    }

    @Test func aTimerCancelledBeforeItRunsOutEndsNothing() async {
        let clock = ManualClock()
        let timer = Task { await QuitExemptions.runOut(on: clock) }
        #expect(await eventually { clock.sleeperCount == 1 })

        timer.cancel()

        let ranOut = await timer.value
        #expect(!ranOut)
    }
}
