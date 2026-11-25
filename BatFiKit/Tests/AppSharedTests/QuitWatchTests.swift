//
//  QuitWatchTests.swift
//  BatFi
//
//  Unit tests for how long the high-energy list waits for an app it asked to quit, and for
//  how long it keeps saying the app is still open.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct QuitWatchTests {
    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"
    private let xcode = "com.apple.dt.Xcode"

    // MARK: - The timeout

    @Test func anAppAskedToQuitIsWatchedForTenSeconds() {
        #expect(QuitWatch.timeout == .seconds(10))
    }

    /// Whether or not it could be asked: an app that is gone has quit.
    @Test(arguments: [true, false], [Duration.zero, .seconds(3), .seconds(10), .seconds(60)])
    func anAppThatIsNoLongerRunningHasQuit(asked: Bool, elapsed: Duration) {
        #expect(QuitWatch.verdict(asked: asked, isRunning: false, elapsed: elapsed) == .quit)
    }

    @Test(arguments: [Duration.zero, .seconds(5), .milliseconds(9_999)])
    func anAppStillRunningWithinTheTimeoutIsStillAwaited(elapsed: Duration) {
        #expect(QuitWatch.verdict(asked: true, isRunning: true, elapsed: elapsed) == .waiting)
    }

    /// Past this point it is most likely showing a dialog — unsaved changes, a download in
    /// progress — and nothing is gained by watching longer. It is never forced.
    @Test(arguments: [Duration.seconds(10), .seconds(11), .seconds(60)])
    func anAppStillRunningOnceTheTimeoutIsUpIsStillOpen(elapsed: Duration) {
        #expect(QuitWatch.verdict(asked: true, isRunning: true, elapsed: elapsed) == .stillOpen)
    }

    /// Nothing is on its way to quitting it, so there is nothing to wait for.
    @Test(arguments: [Duration.zero, .seconds(5), .seconds(60)])
    func anAppThatCouldNotBeAskedIsSaidSoAtOnce(elapsed: Duration) {
        #expect(QuitWatch.verdict(asked: false, isRunning: true, elapsed: elapsed) == .couldNotAsk)
    }

    // MARK: - The hints

    @Test func aHintIsShownForThirtySeconds() {
        #expect(QuitWatch.hintLifetime == .seconds(30))
    }

    @Test func onlyTheOutcomesAreHints() {
        #expect(!QuitProgress.quitting.isHint)
        #expect(QuitProgress.stillOpen.isHint)
        #expect(QuitProgress.couldNotAsk.isHint)
    }

    // MARK: - Keeping the list honest

    @Test(arguments: [QuitProgress.stillOpen, .couldNotAsk])
    func aHintStaysWhileTheListShowsTheAppRunning(hint: QuitProgress) {
        let progress = QuitWatch.reconciled([slack: hint], runningBundleIDs: [slack, safari])

        #expect(progress == [slack: hint])
    }

    /// The app got round to quitting after all, or has dropped out of the list: the hint
    /// would no longer be true.
    @Test(arguments: [QuitProgress.stillOpen, .couldNotAsk], [Set<String>(), ["com.apple.Safari"]])
    func aHintGoesOnceTheAppIsNoLongerListedAsRunning(hint: QuitProgress, running: Set<String>) {
        #expect(QuitWatch.reconciled([slack: hint], runningBundleIDs: running).isEmpty)
    }

    /// Its watch decides when a quit in progress is over, not a list that may have been read
    /// before the app was asked.
    @Test(arguments: [Set<String>(), ["com.tinyspeck.slackmacgap"]])
    func aQuitInProgressIsKeptWhateverTheListSays(running: Set<String>) {
        #expect(QuitWatch.reconciled([slack: .quitting], runningBundleIDs: running) == [slack: .quitting])
    }

    @Test func eachAppIsReconciledOnItsOwn() {
        let progress = QuitWatch.reconciled(
            [slack: .stillOpen, safari: .stillOpen, xcode: .quitting],
            runningBundleIDs: [safari]
        )

        #expect(progress == [safari: .stillOpen, xcode: .quitting])
    }

    // MARK: - An app seen gone

    @Test func anAppSeenGoneStopsBeingListedAsRunningAtOnce() throws {
        let url = URL(fileURLWithPath: "/Applications/Slack.app", isDirectory: true)
        let info = TopCoalitionInfo(topCoalitions: [
            coalition(slack, isRunning: true, bundleURL: url),
            coalition(safari, isRunning: true),
        ])

        let updated = info.markingNotRunning(slack)

        let gone = try #require(updated.topCoalitions.first)
        #expect(gone.bundleIdentifier == slack)
        #expect(!gone.isRunning)
        // Still offered the tortoise until the next report of the list says otherwise:
        // slowing an app down is a setting, not an action on the running app.
        #expect(gone.canOfferActions)
        #expect(gone.canSlowDown)
        #expect(gone.bundleURL == url)
        #expect(gone.energyImpact == 500)
        #expect(updated.topCoalitions.last == info.topCoalitions.last)
    }

    @Test func markingAnAppThatIsNotListedChangesNothing() {
        let info = TopCoalitionInfo(topCoalitions: [coalition(safari, isRunning: true)])

        #expect(info.markingNotRunning(slack) == info)
    }

    private func coalition(_ bundleID: String, isRunning: Bool, bundleURL: URL? = nil) -> Coalition {
        Coalition(
            bundleIdentifier: bundleID,
            energyImpact: 500,
            icon: nil,
            displayName: nil,
            bundleURL: bundleURL,
            isRunning: isRunning,
            canOfferActions: true,
            canSlowDown: true
        )
    }
}
