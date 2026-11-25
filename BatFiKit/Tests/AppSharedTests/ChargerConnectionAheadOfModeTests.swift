//
//  ChargerConnectionAheadOfModeTests.swift
//  BatFi
//
//  On plug-in the icon and the banner waited for the charge-limit apply, which on macOS 27
//  with a sub-80% limit can take up to 45 s: powerd's policy list is empty on battery, so the
//  first pass after every plug-in re-writes the limit and waits for adoption. The connection
//  is now published ahead of the apply, marked as not yet having a mode for it, and the
//  banner waits for the mode.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargerConnectionAheadOfModeTests {
    private typealias Memory = ModeChangeAnnouncement.Memory

    /// On battery above the limit: the mode BatFi last applied, with the charger out.
    private var onBatteryAboveLimit: AppChargingMode {
        AppChargingMode(mode: .inhibit, userTempOverride: nil, chargerConnected: false)
    }

    private func seen(_ mode: AppChargingMode) -> ModeChangeAnnouncement.Seen {
        .init(mode: mode, limit: 55, automationRuleName: nil)
    }

    // MARK: - What to publish ahead of the apply

    @Test func aPlugInIsPublishedAheadOfTheApply() {
        #expect(ChargerConnection.connectionToPublishAheadOfMode(published: onBatteryAboveLimit, resolved: true) == true)
    }

    @Test func anUnplugIsPublishedAheadOfTheApply() {
        let plugged = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        #expect(ChargerConnection.connectionToPublishAheadOfMode(published: plugged, resolved: false) == false)
    }

    /// Every pass that does not change the connection must leave the published state alone,
    /// or each one would mark a known mode as pending again.
    @Test func anUnchangedConnectionIsNotRepublished() {
        #expect(ChargerConnection.connectionToPublishAheadOfMode(published: onBatteryAboveLimit, resolved: false) == nil)
        let pending = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        #expect(ChargerConnection.connectionToPublishAheadOfMode(published: pending, resolved: true) == nil)
    }

    @Test func nothingIsPublishedBeforeTheFirstMode() {
        let initial = AppChargingMode(mode: .initial, userTempOverride: nil, chargerConnected: false)
        #expect(ChargerConnection.connectionToPublishAheadOfMode(published: initial, resolved: true) == nil)
    }

    // MARK: - A fetch of the helper's status while the mode is awaited

    /// A power-supplying USB-C display fires a power-source change and a screen change at
    /// once. The screen handler re-reads the helper's status while the main pass is still
    /// inside the apply; the connection it reads is the one already published ahead of the
    /// mode, so the mode is still not known and the mark has to survive the re-read.
    @Test func aFetchWithTheSameConnectionKeepsTheModeAwaited() {
        let early = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        #expect(ChargerConnection.isAwaitingModeAfterFetch(published: early, fetchedConnected: true))
    }

    /// The re-read reports a different connection: the charger came out again, and whatever
    /// was awaited for the earlier one is moot.
    @Test func aFetchWithADifferentConnectionDropsTheMark() {
        let early = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        #expect(!ChargerConnection.isAwaitingModeAfterFetch(published: early, fetchedConnected: false))
    }

    /// Nothing outstanding — an applier already published the mode — so the fetch publishes
    /// a mode that is the news.
    @Test func aFetchWithNothingAwaitedDoesNotMarkIt() {
        let plugged = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        #expect(!ChargerConnection.isAwaitingModeAfterFetch(published: plugged, fetchedConnected: true))
        #expect(!ChargerConnection.isAwaitingModeAfterFetch(published: onBatteryAboveLimit, fetchedConnected: true))
    }

    /// The first mode of the session is derived by a fetch, from `.initial`, which is never
    /// published ahead of a mode, so that first mode stays announceable.
    @Test func theFirstFetchFromInitialIsAnnounceable() {
        let initial = AppChargingMode(mode: .initial, userTempOverride: nil, chargerConnected: false)
        #expect(!ChargerConnection.isAwaitingModeAfterFetch(published: initial, fetchedConnected: true))
        let first = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        #expect(ModeChangeAnnouncement.consideration(of: first, manageCharging: true) == .announce)
    }

    /// The scenario end to end: the plug-in is published ahead of its mode, the screen
    /// handler's fetch lands while the apply waits, then the applier publishes the mode it
    /// derived. One banner, naming the derived mode — not the helper's raw mode first.
    @Test func aFetchDuringASlowApplyGivesOneBannerNamingTheDerivedMode() {
        var memory = Memory()
        var posted: [String] = []
        func deliver(_ mode: AppChargingMode) {
            switch ModeChangeAnnouncement.consideration(of: mode, manageCharging: true) {
            case .skip:
                memory.skip(mode)
            case .awaitMode:
                break
            case .announce:
                let text = mode.stateDescription
                if memory.decide(seen(mode), title: text, body: "") == .post {
                    posted.append(text)
                }
            }
        }

        deliver(onBatteryAboveLimit)
        let early = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        deliver(early)
        // The screen handler's fetch: the helper reports it charging, and the connection
        // matches what is published.
        let fetched = AppChargingMode(
            mode: .charging,
            userTempOverride: nil,
            chargerConnected: true,
            isAwaitingModeForChargerChange: ChargerConnection.isAwaitingModeAfterFetch(
                published: early,
                fetchedConnected: true
            )
        )
        deliver(fetched)
        #expect(posted.isEmpty)
        let derived = AppChargingMode(
            mode: .inhibit,
            userTempOverride: nil,
            chargerConnected: true,
            systemIsDischargingToLimit: true
        )
        deliver(derived)
        #expect(posted == [derived.stateDescription])
    }

    // MARK: - The published state

    @Test func theEarlyStateCarriesTheConnectionAndEverythingElseAcross() {
        let before = AppChargingMode(
            mode: .inhibit,
            userTempOverride: .init(limit: 40),
            chargerConnected: false,
            systemIsDischargingToLimit: true,
            systemIsHoldingBelowLimit: false,
            systemIsChargingPastLimit: false,
            isHoldingFullChargeUntilUnplugged: true
        )
        let early = before.withChargerConnected(true, awaitingMode: true)
        #expect(early.chargerConnected)
        #expect(early.isAwaitingModeForChargerChange)
        #expect(early.mode == before.mode)
        #expect(early.userTempOverride == before.userTempOverride)
        #expect(early.systemIsDischargingToLimit)
        #expect(early.isHoldingFullChargeUntilUnplugged)
        #expect(early != before.withChargerConnected(true))
    }

    /// The icon draws the plug-in at once, from the early state.
    @Test func theIconShowsThePlugInBeforeTheApplyReturns() {
        let early = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        #expect(BatteryIndicatorMode(appChargingMode: onBatteryAboveLimit) == .discharging)
        #expect(BatteryIndicatorMode(appChargingMode: early) != .discharging)
    }

    // MARK: - The banner

    @Test func theBannerWaitsForTheModeOnAPlugIn() {
        let early = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        #expect(ModeChangeAnnouncement.consideration(of: early, manageCharging: true) == .awaitMode)
    }

    /// An unplug ends the charging session whatever the mode was, so it is acted on at once.
    @Test func anEarlyUnplugIsSkippedAtOnce() {
        let plugged = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        let early = plugged.withChargerConnected(false, awaitingMode: true)
        #expect(ModeChangeAnnouncement.consideration(of: early, manageCharging: true) == .skip)
    }

    @Test func theConsiderationKeepsTheExistingRules() {
        let plugged = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        let initial = AppChargingMode(mode: .initial, userTempOverride: nil, chargerConnected: true)
        #expect(ModeChangeAnnouncement.consideration(of: plugged, manageCharging: true) == .announce)
        #expect(ModeChangeAnnouncement.consideration(of: plugged, manageCharging: false) == .skip)
        #expect(ModeChangeAnnouncement.consideration(of: initial, manageCharging: true) == .skip)
        #expect(ModeChangeAnnouncement.consideration(of: onBatteryAboveLimit, manageCharging: true) == .skip)
    }

    /// The whole plug-in, with an apply slower than the 2 s debounce: the early state is
    /// delivered on its own, then the applier publishes the connection again and the mode it
    /// derived. Exactly one banner, naming the mode that was derived for the charger.
    @Test func aSlowApplyGivesOneBannerNamingTheDerivedMode() {
        var memory = Memory()
        var posted: [String] = []
        func deliver(_ mode: AppChargingMode) {
            switch ModeChangeAnnouncement.consideration(of: mode, manageCharging: true) {
            case .skip:
                memory.skip(mode)
            case .awaitMode:
                break
            case .announce:
                let text = mode.stateDescription
                if memory.decide(seen(mode), title: text, body: "") == .post {
                    posted.append(text)
                }
            }
        }

        deliver(onBatteryAboveLimit)
        // Ahead of the apply; the debounce lets it through on its own because the apply is slow.
        let early = onBatteryAboveLimit.withChargerConnected(true, awaitingMode: true)
        deliver(early)
        #expect(posted.isEmpty)
        // The apply returned; the applier derived macOS draining to the limit.
        let derived = AppChargingMode(
            mode: .inhibit,
            userTempOverride: nil,
            chargerConnected: true,
            systemIsDischargingToLimit: true
        )
        deliver(derived)
        #expect(posted == [derived.stateDescription])
    }

    /// Why the banner has to wait rather than announce the early state: the pre-plug mode
    /// rendered with the charger connected is a plain "Inhibiting charging", and the drain
    /// that follows is then a quiet sub-state change — so the wrong sentence is the only one
    /// the user would ever get.
    @Test func announcingTheEarlyStateWouldPostTheWrongSentenceAndSwallowTheRightOne() {
        var memory = Memory()
        let stale = onBatteryAboveLimit.withChargerConnected(true)
        let derived = AppChargingMode(
            mode: .inhibit,
            userTempOverride: nil,
            chargerConnected: true,
            systemIsDischargingToLimit: true
        )
        memory.skip(onBatteryAboveLimit)
        #expect(memory.decide(seen(stale), title: stale.stateDescription, body: "") == .post)
        #expect(memory.decide(seen(derived), title: derived.stateDescription, body: "") == .quietSubStateChange)
    }
}
