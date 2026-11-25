//
//  ChargeLimitNotHoldingWarningTests.swift
//  BatFi
//
//  The notification raised once a run of the limit not holding has lasted ten minutes. When
//  another tool that can write the limit is installed, it is named, with how to remove it;
//  otherwise the generic warning is unchanged. The battery CLI on macOS 27-era firmware can't
//  write the limit, so it is never the one blamed.
//

import Foundation
import L10n
import Testing

@testable import AppShared
@testable import Shared

@Suite struct ChargeLimitNotHoldingWarningTests {
    private let batteryCLI = DetectedChargeTool(tool: .batteryCLI, matchedFootprint: .path("/usr/local/bin/battery"))
    private let alDente = DetectedChargeTool(tool: .alDente, matchedFootprint: .bundleID("com.apphousekitchen.aldente-pro"))
    private let battHomebrew = DetectedChargeTool(tool: .batt, matchedFootprints: [
        .path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist"), .path("/opt/homebrew/bin/batt"),
    ])
    private let battApp = DetectedChargeTool(
        tool: .batt,
        matchedFootprints: [.path("/Library/LaunchDaemons/cc.chlc.batt.plist"), .path("/usr/local/bin/batt"), .bundleID("cc.chlc.batt")]
    )

    private let quoted: (String) -> String = { "“\($0)”" }

    // MARK: - Which tool is named

    @Test func noToolsMeansNoSuspect() {
        #expect(ChargeLimitNotHoldingWarning.suspect(in: [], backend: .chte) == nil)
    }

    @Test(arguments: [ChargeBackend.firmwareRange, .systemChargeLimit])
    func batteryCLIOnMacOS27FirmwareIsNotASuspect(backend: ChargeBackend) {
        #expect(ChargeLimitNotHoldingWarning.suspect(in: [batteryCLI], backend: backend) == nil)
    }

    @Test(arguments: [ChargeBackend?.some(.chte), .some(.legacyCH0BC), nil])
    func batteryCLIElsewhereIsASuspect(backend: ChargeBackend?) {
        #expect(ChargeLimitNotHoldingWarning.suspect(in: [batteryCLI], backend: backend) == batteryCLI)
    }

    @Test func theFirstToolThatCanWriteTheLimitIsNamed() {
        let suspect = ChargeLimitNotHoldingWarning.suspect(in: [batteryCLI, alDente, battHomebrew], backend: .firmwareRange)
        #expect(suspect == alDente)
    }

    // MARK: - What it says

    @Test func withoutASuspectTheGenericWarningIsUnchanged() {
        let warning = ChargeLimitNotHoldingWarning(limit: "80%", detected: [batteryCLI], backend: .firmwareRange, markingCommand: quoted)
        #expect(warning.suspect == nil)
        #expect(warning.title == L10n.Notifications.Notification.Title.chargeLimitNotHolding)
        #expect(warning.body == L10n.Notifications.Notification.Body.chargeLimitNotHolding("80%"))
    }

    @Test func withASuspectTheBodyNamesItAndHowToRemoveIt() {
        let warning = ChargeLimitNotHoldingWarning(limit: "80%", detected: [alDente], backend: .chte, markingCommand: quoted)
        #expect(warning.suspect == alDente)
        #expect(warning.title == L10n.Notifications.Notification.Title.chargeLimitNotHolding)
        let removal = L10n.OtherChargeTools.removeAlDente("AlDente")
        #expect(warning.body == L10n.OtherChargeTools.notificationChargeLimitNotHolding(limit: "80%", toolName: "AlDente", removal: removal))
        #expect(warning.body.contains("80%"))
        #expect(warning.body.contains("AlDente"))
        #expect(warning.body.contains(removal))
    }

    @Test func commandsInTheNotificationAreMarkedAsGivenNotAsMarkdown() {
        let warning = ChargeLimitNotHoldingWarning(limit: "75%", detected: [battHomebrew], backend: .chte, markingCommand: quoted)
        #expect(warning.body.contains("“sudo batt disable”"))
        #expect(warning.body.contains("“sudo brew services stop batt”"))
        #expect(warning.body.contains("“brew uninstall batt”"))
        #expect(!warning.body.contains("`"))
    }

    /// A tool with several footprints takes several steps to remove; the notification
    /// carries all of them, as Settings does, so following it clears the warning there too.
    @Test func everyRemovalStepIsInTheNotification() {
        let warning = ChargeLimitNotHoldingWarning(limit: "80%", detected: [battApp], backend: .chte, markingCommand: quoted)
        let strings = L10n.OtherChargeTools.self
        let removal = [
            strings.removeBattApp("batt", app: "batt.app"),
            strings.thenRunCommand("“sudo rm /usr/local/bin/batt”"),
            strings.thenMoveToTrash("batt.app"),
        ].joined(separator: " ")
        #expect(warning.body == strings.notificationChargeLimitNotHolding(limit: "80%", toolName: "batt", removal: removal))
        #expect(!warning.body.contains("`"))
    }
}
