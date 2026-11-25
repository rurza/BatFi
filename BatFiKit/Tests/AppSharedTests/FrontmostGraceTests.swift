//
//  FrontmostGraceTests.swift
//  BatFi
//
//  Unit tests for the bookkeeping that gives an app leaving the front a few seconds before
//  it may be slowed down again, and gives it back at once when it comes to the front.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct FrontmostGraceTests {
    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"
    private let batFi = "software.micropixels.BatFi"

    @Test func theFirstReportOfTheFrontEvaluatesAtOnceAndStartsNoGrace() {
        var grace = FrontmostGrace()

        let change = grace.frontmostChanged(pid: 100, bundleID: slack)

        #expect(change == FrontmostGrace.Change(evaluateNow: true, graceStarted: nil))
        #expect(grace.frontmostPID == 100)
        #expect(grace.frontmostBundleID == slack)
        #expect(grace.recentlyActiveBundleIDs.isEmpty)
    }

    @Test func anAppLeavingTheFrontStartsItsGraceAndTheOneComingInIsEvaluatedAtOnce() throws {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)

        let change = grace.frontmostChanged(pid: 200, bundleID: safari)

        #expect(change.evaluateNow)
        let started = try #require(change.graceStarted)
        #expect(started.bundleID == slack)
        #expect(grace.recentlyActiveBundleIDs == [slack])
        #expect(grace.frontmostPID == 200)
        #expect(grace.frontmostBundleID == safari)
    }

    @Test func theGraceEndingLetsTheAppBeSlowedAgainAndAsksForAnEvaluation() throws {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)
        let started = try #require(grace.frontmostChanged(pid: 200, bundleID: safari).graceStarted)

        let ended = grace.graceEnded(started)
        #expect(ended)
        #expect(grace.recentlyActiveBundleIDs.isEmpty)
        // Ending it twice changes nothing more.
        let endedAgain = grace.graceEnded(started)
        #expect(!endedAgain)
    }

    @Test func comingBackDuringTheGraceEndsItAndItsTimerThenChangesNothing() throws {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)
        let started = try #require(grace.frontmostChanged(pid: 200, bundleID: safari).graceStarted)

        let back = grace.frontmostChanged(pid: 100, bundleID: slack)

        #expect(back.evaluateNow)
        #expect(back.graceStarted?.bundleID == safari)
        #expect(grace.recentlyActiveBundleIDs == [safari])
        let staleEnded = grace.graceEnded(started)
        #expect(!staleEnded)
        #expect(grace.recentlyActiveBundleIDs == [safari])
    }

    @Test func leavingAgainRestartsTheGraceSoOnlyTheLatestTimerEndsIt() throws {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)
        let first = try #require(grace.frontmostChanged(pid: 200, bundleID: safari).graceStarted)
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)
        let second = try #require(grace.frontmostChanged(pid: 200, bundleID: safari).graceStarted)

        #expect(first != second)
        let firstEnded = grace.graceEnded(first)
        #expect(!firstEnded)
        #expect(grace.recentlyActiveBundleIDs.contains(slack))
        let secondEnded = grace.graceEnded(second)
        #expect(secondEnded)
        #expect(!grace.recentlyActiveBundleIDs.contains(slack))
    }

    @Test func theSameAppReportedAgainChangesNothing() {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)

        let change = grace.frontmostChanged(pid: 100, bundleID: slack)

        #expect(change == FrontmostGrace.Change(evaluateNow: false, graceStarted: nil))
        #expect(grace.recentlyActiveBundleIDs.isEmpty)
    }

    @Test func anotherInstanceOfTheSameAppComingToTheFrontIsEvaluatedWithoutAGrace() {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)

        let change = grace.frontmostChanged(pid: 150, bundleID: slack)

        #expect(change == FrontmostGrace.Change(evaluateNow: true, graceStarted: nil))
        #expect(grace.frontmostPID == 150)
        #expect(grace.recentlyActiveBundleIDs.isEmpty)
    }

    @Test func anAppWithoutABundleIdentifierLeavingStartsNoGrace() {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 400, bundleID: nil)

        let change = grace.frontmostChanged(pid: 100, bundleID: slack)

        #expect(change == FrontmostGrace.Change(evaluateNow: true, graceStarted: nil))
        #expect(grace.recentlyActiveBundleIDs.isEmpty)
    }

    /// Clicking BatFi's status item brings BatFi to the front, and closing the menu hands the
    /// front back: the app in use must come out of it without ever having been slowed.
    @Test func theStatusItemFlapLeavesTheAppInUseUnslowed() throws {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)
        let flap = try #require(grace.frontmostChanged(pid: 900, bundleID: batFi).graceStarted)
        #expect(grace.recentlyActiveBundleIDs == [slack])

        _ = grace.frontmostChanged(pid: 100, bundleID: slack)

        #expect(!grace.recentlyActiveBundleIDs.contains(slack))
        let flapEnded = grace.graceEnded(flap)
        #expect(!flapEnded)
    }

    @Test func anAppThatLeftTheFrontIsSparedUntilFiveSecondsHavePassed() async throws {
        var grace = FrontmostGrace()
        _ = grace.frontmostChanged(pid: 100, bundleID: slack)
        let started = try #require(grace.frontmostChanged(pid: 200, bundleID: safari).graceStarted)
        let clock = ManualClock()
        let timer = Task { await FrontmostGrace.runOut(on: clock) }
        #expect(await eventually { clock.sleeperCount == 1 })

        clock.advance(by: .milliseconds(4999))
        #expect(clock.sleeperCount == 1)
        #expect(grace.recentlyActiveBundleIDs == [slack])

        clock.advance(by: .milliseconds(1))
        let ranOut = await timer.value
        #expect(ranOut)
        let ended = grace.graceEnded(started)
        #expect(ended)
        #expect(grace.recentlyActiveBundleIDs.isEmpty)
    }

    @Test func aGraceTimerCancelledBeforeItRunsOutEndsNothing() async {
        let clock = ManualClock()
        let timer = Task { await FrontmostGrace.runOut(on: clock) }
        #expect(await eventually { clock.sleeperCount == 1 })

        timer.cancel()

        let ranOut = await timer.value
        #expect(!ranOut)
    }
}
