//
//  OtherChargeToolsWarningTests.swift
//  BatFi
//
//  What Charging settings and the menu say about another charge-control tool. The one
//  claim that must never be made is that the battery CLI fights over the limit on macOS
//  27-era firmware, where it has no working charge-inhibit key left — so the choice of
//  sentence is pinned per backend, and every removal command must reach the user verbatim.
//

import Foundation
import L10n
import Testing

@testable import AppShared
import L10n
@testable import Shared

@Suite struct OtherChargeToolsWarningTests {
    private let batteryCLI = DetectedChargeTool(tool: .batteryCLI, matchedFootprint: .path("/usr/local/bin/battery"))
    private let alDente = DetectedChargeTool(tool: .alDente, matchedFootprint: .bundleID("com.apphousekitchen.aldente-pro"))
    private let batteryToolkit = DetectedChargeTool(tool: .batteryToolkit, matchedFootprint: .bundleID("me.mhaeuser.BatteryToolkit"))
    private let battScript = DetectedChargeTool(tool: .batt, matchedFootprint: .path("/usr/local/bin/batt"))
    private let battHomebrew = DetectedChargeTool(tool: .batt, matchedFootprints: [
        .path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist"), .path("/opt/homebrew/bin/batt"),
    ])
    private let bclm = DetectedChargeTool(tool: .bclm, matchedFootprint: .path("/usr/local/bin/bclm"))

    private let strings = L10n.OtherChargeTools.self

    // MARK: - What it fights over

    @Test(arguments: [ChargeBackend.firmwareRange, .systemChargeLimit])
    func batteryCLIOnMacOS27FirmwareNamesTheLightAndDischargeNotTheLimit(backend: ChargeBackend) {
        let warning = OtherChargeToolWarning(detected: batteryCLI, backend: backend)
        #expect(warning.problem == strings.magSafeLightAndDischargeProblem("battery CLI"))
    }

    @Test(arguments: [ChargeBackend?.some(.chte), .some(.legacyCH0BC), .some(.unsupported), nil])
    func batteryCLIElsewhereNamesTheLimit(backend: ChargeBackend?) {
        let warning = OtherChargeToolWarning(detected: batteryCLI, backend: backend)
        #expect(warning.problem == strings.chargeLimitProblem("battery CLI"))
    }

    @Test func otherToolsNameTheLimitEvenOnMacOS27Firmware() {
        for detected in [alDente, batteryToolkit, battScript, bclm] {
            let warning = OtherChargeToolWarning(detected: detected, backend: .firmwareRange)
            #expect(warning.problem == strings.chargeLimitProblem(detected.tool.displayName))
        }
    }

    // MARK: - The English itself

    /// The English the catalog holds for `key`, whatever language the test runs in. Read
    /// from the catalog source: the compiled en.lproj leaves out keys whose English still
    /// comes from the code's default, and the sync script keeps the two the same.
    private func english(_ key: String) throws -> String {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/L10n/Localizable.xcstrings")
            .standardizedFileURL
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any], "\(key) missing from the catalog")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let english = try #require(localizations["en"] as? [String: Any])
        let unit = try #require(english["stringUnit"] as? [String: Any])
        return try #require(unit["value"] as? String)
    }

    /// The tests above only pin which key is used; these pin what it says. On macOS
    /// 27-era firmware the battery CLI cannot touch the limit, so its sentence must be
    /// about the light and Run on Battery and must not claim it overrides the limit.
    @Test func theMacOS27SentenceIsAboutTheLightNotTheLimit() throws {
        let text = String(format: try english("other_charge_tools.settings.problem.magsafe_light_and_discharge"), "battery CLI")
        #expect(text.hasPrefix("battery CLI is also installed"))
        #expect(text.contains("MagSafe"))
        #expect(text.contains("Run on Battery"))
        #expect(!text.contains("override BatFi’s charge limit"))
        #expect(text.contains("can’t change your charge limit"))
    }

    @Test func theChargeLimitSentenceSaysItCanOverrideTheLimit() throws {
        let text = String(format: try english("other_charge_tools.settings.problem.charge_limit"), "battery CLI")
        #expect(text.contains("can override BatFi’s charge limit"))
        #expect(!text.contains("MagSafe"))
    }

    // MARK: - How to remove it

    @Test func batteryCLIRemovalShowsItsCommandVerbatim() {
        let warning = OtherChargeToolWarning(detected: batteryCLI, backend: .chte)
        #expect(warning.removal == strings.removeWithCommand("battery CLI", command: "`battery uninstall`"))
    }

    @Test func batteryCLIWithItsAppAlsoTrashesTheApp() {
        let detected = DetectedChargeTool(
            tool: .batteryCLI,
            matchedFootprints: [.path("/usr/local/bin/battery"), .bundleID("co.palokaj.battery")],
            applications: [URL(fileURLWithPath: "/Applications/Battery.app")]
        )
        let warning = OtherChargeToolWarning(detected: detected, backend: .chte)
        #expect(warning.removal == strings.removeWithCommand("battery CLI", command: "`battery uninstall`") + " " + strings.thenMoveToTrash("Battery.app"))
    }

    @Test func anAppAloneIsMovedToTheTrash() {
        let detected = DetectedChargeTool(tool: .batteryCLI, matchedFootprint: .bundleID("co.palokaj.battery"))
        let warning = OtherChargeToolWarning(detected: detected, backend: .chte)
        #expect(warning.removal == strings.removeByMovingToTrash("battery CLI", apps: "Battery.app"))
    }

    @Test func battScriptRemovalAlsoDeletesTheBinary() {
        let warning = OtherChargeToolWarning(detected: battScript, backend: .chte)
        #expect(warning.removal == strings.removeWithCommand("batt", command: "`sudo rm /usr/local/bin/batt`"))
    }

    @Test func battHomebrewRemovalListsEveryCommandInOrder() {
        let warning = OtherChargeToolWarning(detected: battHomebrew, backend: .chte)
        let list = ListFormatter.localizedString(byJoining: ["`sudo batt disable`", "`sudo brew services stop batt`", "`brew uninstall batt`"])
        #expect(warning.removal == strings.removeWithCommands("batt", commands: list))
        #expect(warning.removal.contains("`sudo brew services stop batt`"))
        #expect(warning.removal.contains("`brew uninstall batt`"))
    }

    @Test func battAppIsUninstalledFromInsideThenTrashed() {
        let detected = DetectedChargeTool(
            tool: .batt,
            matchedFootprints: [.path("/Library/LaunchDaemons/cc.chlc.batt.plist"), .path("/usr/local/bin/batt"), .bundleID("cc.chlc.batt")]
        )
        let warning = OtherChargeToolWarning(detected: detected, backend: .chte)
        #expect(warning.removal == [
            strings.removeBattApp("batt", app: "batt.app"),
            strings.thenRunCommand("`sudo rm /usr/local/bin/batt`"),
            strings.thenMoveToTrash("batt.app"),
        ].joined(separator: " "))
    }

    @Test func bclmRemovalUnpersistsThenDeletesTheBinary() {
        let detected = DetectedChargeTool(tool: .bclm, matchedFootprints: [
            .path("/Library/LaunchDaemons/com.zackelia.bclm.plist"), .path("/usr/local/bin/bclm"),
        ])
        let warning = OtherChargeToolWarning(detected: detected, backend: .chte)
        let list = ListFormatter.localizedString(byJoining: ["`sudo bclm unpersist`", "`sudo rm /usr/local/bin/bclm`"])
        #expect(warning.removal == strings.removeWithCommands("bclm", commands: list))
    }

    @Test func aLeftoverBclmBinaryIsDeletedPrecisely() {
        let warning = OtherChargeToolWarning(detected: bclm, backend: .chte)
        #expect(warning.removal == strings.removeWithCommand("bclm", command: "`sudo rm /usr/local/bin/bclm`"))
    }

    @Test func alDenteRemovalPointsAtItsOwnSettings() {
        let warning = OtherChargeToolWarning(detected: alDente, backend: .chte)
        #expect(warning.removal == strings.removeAlDente("AlDente"))
    }

    @Test func batteryToolkitRemovalPointsAtItsInAppRemoval() {
        let warning = OtherChargeToolWarning(detected: batteryToolkit, backend: .chte)
        #expect(warning.removal == strings.removeBatteryToolkit("Battery Toolkit"))
    }

    /// The English of the follow-on sentences, as a reader sees them.
    @Test func theFollowOnSentencesReadAsEnglish() throws {
        #expect(String(format: try english("other_charge_tools.settings.removal.then_trash"), "batt.app") == "Then move batt.app to the Trash.")
        #expect(String(format: try english("other_charge_tools.settings.removal.then_command"), "`x`") == "Then run `x` in Terminal.")
        #expect(String(format: try english("other_charge_tools.settings.removal.trash"), "battery CLI", "Battery.app") == "To remove battery CLI, move Battery.app to the Trash.")
    }

    @Test func warningIsIdentifiedByItsTool() {
        #expect(OtherChargeToolWarning(detected: battHomebrew, backend: nil).id == .batt)
    }

    // MARK: - Menu row

    @Test func menuRowIsAbsentWithNoTools() {
        #expect(OtherChargeToolWarning.menuTitle(for: []) == nil)
    }

    @Test func menuRowNamesASingleTool() {
        #expect(OtherChargeToolWarning.menuTitle(for: [batteryCLI]) == strings.menuOneTool("battery CLI"))
    }

    @Test func menuRowDoesNotNameSeveralTools() {
        #expect(OtherChargeToolWarning.menuTitle(for: [batteryCLI, alDente]) == strings.menuSeveralTools)
    }

    @Test func menuDetailMatchesTheNumberOfTools() {
        #expect(OtherChargeToolWarning.menuDetail(for: []) == nil)
        #expect(OtherChargeToolWarning.menuDetail(for: [bclm]) == strings.menuDetailOneTool)
        #expect(OtherChargeToolWarning.menuDetail(for: [bclm, alDente]) == strings.menuDetailSeveralTools)
    }
}
