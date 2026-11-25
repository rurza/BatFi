//
//  SlowDownMenuButtonTests.swift
//  BatFi
//
//  Unit tests for which button, if any, a row of the menu's high-energy list offers.
//

import Testing

@testable import AppShared

@Suite struct SlowDownMenuButtonTests {
    typealias Reason = SlowDownStatus.Reason

    static let everyStatus: [SlowDownStatus?] =
        [nil, .slowed, .notSlowed(nil)] + Reason.allCases.map { .notSlowed($0) }

    private func offered(
        isEnabled: Bool = true,
        canSlowDown: Bool = true,
        onBattery: Bool? = true,
        licence: SlowDownStatus.Licence? = .valid,
        isListed: Bool,
        status: SlowDownStatus? = nil
    ) -> SlowDownMenuButton? {
        SlowDownMenuButton.offered(
            isEnabled: isEnabled,
            canSlowDown: canSlowDown,
            onBattery: onBattery,
            licence: licence,
            isListed: isListed,
            status: status
        )
    }

    // MARK: - On battery

    @Test func anAppOutsideTheListIsOfferedToBeSlowedDown() {
        #expect(offered(isListed: false) == .slowDown)
    }

    @Test func aListedAppSlowedNowIsOfferedToStop() {
        #expect(offered(isListed: true, status: .slowed) == .stopSlowing)
    }

    @Test(arguments: [Reason?.none] + Reason.allCases.map(Optional.some))
    func aListedAppNotSlowedNowIsOfferedNothing(reason: Reason?) {
        #expect(offered(isListed: true, status: .notSlowed(reason)) == nil)
    }

    @Test func aListedAppWithNoStatusYetIsOfferedNothing() {
        #expect(offered(isListed: true, status: nil) == nil)
    }

    // MARK: - Not on battery

    /// Even an app the ledger still holds, while a failed give-back waits for its retry.
    @Test(arguments: everyStatus)
    func onTheChargerNoListedAppIsOfferedAnything(status: SlowDownStatus?) {
        #expect(offered(onBattery: false, isListed: true, status: status) == nil)
    }

    @Test func onTheChargerAnAppOutsideTheListIsOfferedNothing() {
        #expect(offered(onBattery: false, isListed: false) == nil)
    }

    @Test(arguments: [false, true])
    func beforeTheFirstReportNothingIsOffered(isListed: Bool) {
        #expect(offered(onBattery: nil, isListed: isListed, status: .slowed) == nil)
    }

    // MARK: - Without an active licence

    /// Adding an app would slow nothing down until a licence is active.
    @Test(arguments: [SlowDownStatus.Licence.invalid, .unknown])
    func withoutAnActiveLicenceAnAppOutsideTheListIsOfferedNothing(licence: SlowDownStatus.Licence) {
        #expect(offered(licence: licence, isListed: false) == nil)
    }

    /// Even an app the ledger still holds, while a failed give-back waits for its retry.
    @Test(arguments: [SlowDownStatus.Licence.invalid, .unknown])
    func withoutAnActiveLicenceNoListedAppIsOfferedAnything(licence: SlowDownStatus.Licence) {
        for status in Self.everyStatus {
            #expect(offered(licence: licence, isListed: true, status: status) == nil)
        }
    }

    @Test(arguments: [false, true])
    func beforeTheLicenceIsReportedNothingIsOffered(isListed: Bool) {
        #expect(offered(licence: nil, isListed: isListed, status: .slowed) == nil)
    }

    // MARK: - Never

    @Test(arguments: [false, true])
    func theMasterSwitchOffOffersNothing(isListed: Bool) {
        #expect(offered(isEnabled: false, isListed: isListed, status: .slowed) == nil)
    }

    @Test(arguments: [false, true])
    func anAppBatFiCannotSlowDownIsOfferedNothing(isListed: Bool) {
        #expect(offered(canSlowDown: false, isListed: isListed, status: .slowed) == nil)
    }
}
