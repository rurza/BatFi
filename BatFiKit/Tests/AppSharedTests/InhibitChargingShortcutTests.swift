//
//  InhibitChargingShortcutTests.swift
//  BatFi
//
//  Whether Settings › Hotkeys offers the "Inhibit charging" shortcut. The status menu
//  withholds the command on firmware that cannot hold charge at its current level; the
//  shortcut recorder is the same command under another name, and offering it there invites
//  the user to bind a key that pauses nothing.
//

import Foundation
import Testing

@testable import Shared

@Suite struct InhibitChargingShortcutTests {
    // MARK: - Backends that can pause on demand

    @Test func offeredWhereTheChargingKeyCanPause() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: ChargeBackend.chte.rawValue))
    }

    @Test func offeredOnTheLegacyChargingKey() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: ChargeBackend.legacyCH0BC.rawValue))
    }

    /// MPX-41: back on macOS 27 firmware, where the inhibit is held by freezing Apple's limit
    /// at the battery's level.
    @Test func offeredUnderTheSystemChargeLimit() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: ChargeBackend.systemChargeLimit.rawValue))
    }

    // MARK: - Backends that cannot hold charge where it is

    /// A band at the current level lets the battery fall five points and charges it back.

    @Test func hiddenUnderTheFirmwareRange() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: ChargeBackend.firmwareRange.rawValue) == false)
    }

    @Test func hiddenWhereNothingIsSupported() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: ChargeBackend.unsupported.rawValue) == false)
    }

    @Test func agreesWithTheBackendForEveryCase() {
        for backend in ChargeBackend.allCases {
            #expect(
                InhibitChargingShortcut.isOffered(rawBackend: backend.rawValue)
                    == backend.canHoldChargeAtCurrentLevel
            )
        }
    }

    // MARK: - A backend not yet known

    /// A Mac whose helper has never answered keeps the row, as it always has — the same
    /// fail-open default as the status menu and the charging manager.
    @Test func offeredWhileTheBackendIsUnknown() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: nil))
    }

    /// A raw value this build does not recognise — written by a newer build, say — is no
    /// evidence against holding charge either.
    @Test func offeredForAnUnrecognisedBackend() {
        #expect(InhibitChargingShortcut.isOffered(rawBackend: "someFutureBackend"))
    }
}
