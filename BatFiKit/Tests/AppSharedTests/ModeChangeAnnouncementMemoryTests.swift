//
//  ModeChangeAnnouncementMemoryTests.swift
//  BatFi
//
//  The plug-in banner went missing on the second plug-in below the limit: the text dedupe
//  outlived the unplug, so "Charging to the limit / The limit is 80%" was the same sentence
//  as last time and was dropped. Field symptom: banners "only sometimes, then never". The
//  dedupe is per charging session now; within one it still stops repeats and quiet sub-states.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ModeChangeAnnouncementMemoryTests {
    private typealias Seen = ModeChangeAnnouncement.Seen
    private typealias Memory = ModeChangeAnnouncement.Memory

    private let title = "New mode: Charging to the limit"
    private let body = "The limit is 80%"

    private var charging: AppChargingMode {
        AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
    }

    private var unplugged: AppChargingMode {
        AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: false)
    }

    private func inhibit(topUp: Bool = false, drain: Bool = false, hold: Bool = false) -> AppChargingMode {
        AppChargingMode(
            mode: .inhibit,
            userTempOverride: nil,
            chargerConnected: true,
            systemIsDischargingToLimit: drain,
            systemIsHoldingBelowLimit: hold,
            systemIsChargingPastLimit: topUp
        )
    }

    private var initial: AppChargingMode {
        AppChargingMode(mode: .initial, userTempOverride: nil, chargerConnected: false)
    }

    private func seen(_ mode: AppChargingMode) -> Seen {
        Seen(mode: mode, limit: 80, automationRuleName: nil)
    }

    /// A memory past its launch baseline: BatFi launched unplugged, so whatever comes next
    /// on the charger is news.
    private func runningMemory() -> Memory {
        var memory = Memory()
        memory.skip(unplugged)
        return memory
    }

    @Test func plugUnplugPlugBelowTheLimitPostsTwice() {
        var memory = runningMemory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
        memory.skip(unplugged)
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
    }

    /// `combineLatest` re-delivers an unchanged mode whenever `manageCharging` ticks; measured
    /// 2026-08-26 as a double banner on launch.
    @Test func aReEmissionWhilePluggedInPostsOnce() {
        var memory = runningMemory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
        #expect(memory.decide(seen(charging), title: title, body: body) == .repeatedText)
    }

    /// Turning management off and on while plugged in is not a new charging session.
    @Test func managementOffAndOnWhilePluggedInDoesNotRepeat() {
        var memory = runningMemory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
        memory.skip(charging)
        #expect(memory.decide(seen(charging), title: title, body: body) == .repeatedText)
    }

    /// `.initial` reports no charger whatever is plugged in, so it is not an unplug.
    @Test func passingThroughInitialDoesNotRepeat() {
        var memory = runningMemory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
        memory.skip(AppChargingMode(mode: .initial, userTempOverride: nil, chargerConnected: false))
        #expect(memory.decide(seen(charging), title: title, body: body) == .repeatedText)
    }

    /// MPX-43: a calibration plateau flapping between macOS's own sub-states posts nothing
    /// after the held mode was announced.
    @Test func aCalibrationPlateauFlappingPostsNothing() {
        var memory = runningMemory()
        let held = "New mode: Charging inhibited"
        #expect(memory.decide(seen(inhibit()), title: held, body: "plain") == .post)
        for mode in [inhibit(topUp: true), inhibit(drain: true), inhibit(topUp: true), inhibit(drain: true), inhibit(hold: true)] {
            #expect(memory.decide(seen(mode), title: held, body: "sub-state") == .quietSubStateChange)
        }
    }

    @Test func aDifferentSentenceStillPostsWithinASession() {
        var memory = runningMemory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
        #expect(memory.decide(seen(inhibit()), title: "New mode: Charging inhibited", body: body) == .post)
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
    }

    // MARK: - The launch baseline
    //
    // Reported from hardware on beta 246: right after a Sparkle relaunch, "New mode: Inhibiting
    // charging" for a battery that had sat at 95% above an 80% limit, on the charger, before
    // and after. The memory started empty in the new process, so the state BatFi found was
    // announced as if it had just changed. The first announceable state is a baseline.

    @Test func theFirstStateAfterLaunchOnTheChargerIsABaseline() {
        var memory = Memory()
        #expect(memory.decide(seen(inhibit()), title: "New mode: Inhibiting charging", body: body) == .baseline)
    }

    /// The baseline counts as said: the same sentence again is a repeat, and macOS draining to
    /// the limit 30 s later stays quiet, as it did in the report.
    @Test func theBaselineIsRememberedAsSeenAndAnnounced() {
        var memory = Memory()
        let held = "New mode: Inhibiting charging"
        #expect(memory.decide(seen(inhibit()), title: held, body: body) == .baseline)
        #expect(memory.decide(seen(inhibit()), title: held, body: body) == .repeatedText)
        #expect(memory.decide(seen(inhibit(drain: true)), title: held, body: "draining") == .quietSubStateChange)
    }

    @Test func aRealChangeAfterTheBaselinePosts() {
        var memory = Memory()
        #expect(memory.decide(seen(inhibit()), title: "New mode: Inhibiting charging", body: body) == .baseline)
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
    }

    /// `.initial` says nothing about the charger, so passing through it at launch keeps the
    /// baseline for the state that follows.
    @Test func initialBeforeTheFirstStateKeepsTheBaseline() {
        var memory = Memory()
        memory.skip(initial)
        #expect(memory.decide(seen(charging), title: title, body: body) == .baseline)
    }

    /// Launched unplugged: plugging in later is news.
    @Test func aPlugInAfterAnUnpluggedLaunchPosts() {
        var memory = Memory()
        memory.skip(initial)
        memory.skip(unplugged)
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
    }

    /// Management off at launch and turned on later: the user's own act, whose result the menu
    /// shows at once, on a charger that never left. The state it produces is the baseline.
    @Test func managementTurnedOnAfterLaunchIsABaseline() {
        var memory = Memory()
        memory.skip(charging)
        #expect(memory.decide(seen(charging), title: title, body: body) == .baseline)
    }

    @Test func anUnplugAfterTheBaselineMakesTheNextPlugInNews() {
        var memory = Memory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .baseline)
        memory.skip(unplugged)
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
    }

    /// Observing restarted — the notification setting turned off and on — takes a new
    /// baseline: the state the battery is already in is not news.
    @Test func forgettingTakesANewBaseline() {
        var memory = runningMemory()
        #expect(memory.decide(seen(charging), title: title, body: body) == .post)
        memory.forget()
        #expect(memory.decide(seen(charging), title: title, body: body) == .baseline)
        #expect(memory.decide(seen(inhibit()), title: "New mode: Inhibiting charging", body: body) == .post)
    }
}
