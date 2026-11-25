//
//  OtherChargeToolsTests.swift
//  BatFi
//
//  Other charge limiters fight BatFi over the SMC, and the user is the only one who can
//  remove them. Detection is by install footprint alone — file existence and Launch
//  Services lookups — so every footprint is pinned here on its own: a typo in one path
//  is a tool BatFi silently stops seeing.
//

import Foundation
import Testing

@testable import Shared

@Suite struct OtherChargeToolsTests {
    private let home = "/Users/tester"

    private func detect(
        paths: Set<String> = [],
        apps: [String: [URL]] = [:],
        home: String? = nil
    ) -> [DetectedChargeTool] {
        OtherChargeToolDetection.detect(
            homeDirectory: home ?? self.home,
            fileExists: { paths.contains($0) },
            applicationURLs: { apps[$0] ?? [] }
        )
    }

    // MARK: - Every footprint, alone

    struct FootprintCase: CustomTestStringConvertible, Sendable {
        let tool: OtherChargeTool
        let footprint: OtherChargeToolFootprint
        var testDescription: String { "\(tool.rawValue): \(footprint)" }
    }

    static let allFootprints: [FootprintCase] = OtherChargeTool.allCases.flatMap { tool in
        tool.footprints.map { FootprintCase(tool: tool, footprint: $0) }
    }

    @Test(arguments: allFootprints)
    func eachFootprintAloneDetectsItsTool(_ testCase: FootprintCase) {
        let detected: [DetectedChargeTool]
        switch testCase.footprint {
        case let .path(path):
            detected = detect(paths: [path])
        case let .homeRelativePath(relative):
            detected = detect(paths: ["\(home)/\(relative)"])
        case let .bundleID(bundleID):
            let appURL = URL(fileURLWithPath: "/Applications/Some.app")
            detected = detect(paths: [appURL.path], apps: [bundleID: [appURL]])
        }
        #expect(detected.map(\.tool) == [testCase.tool])
        #expect(detected.first?.matchedFootprints == [testCase.footprint])
    }

    /// The upstream-verified footprints, spelled out, so that the data above cannot drift
    /// away from them unnoticed. A footprint removed from the table would quietly shrink the
    /// parameterised test; this one fails instead.
    @Test func theTableCarriesEveryVerifiedFootprint() {
        let expected: [OtherChargeTool: [OtherChargeToolFootprint]] = [
            .batteryCLI: [
                .homeRelativePath("Library/LaunchAgents/battery.plist"),
                .path("/usr/local/co.palokaj.battery"),
                .path("/usr/local/bin/battery"),
                .path("/private/etc/sudoers.d/battery"),
                .homeRelativePath(".battery/maintain.percentage"),
                .bundleID("co.palokaj.battery"),
            ],
            .alDente: [
                .bundleID("com.apphousekitchen.aldente-pro"),
                .path("/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper"),
                .path("/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist"),
                .bundleID("com.davidwernhart.AlDente"),
                .path("/Library/PrivilegedHelperTools/com.davidwernhart.Helper"),
                .path("/Library/LaunchDaemons/com.davidwernhart.Helper.plist"),
            ],
            .batteryToolkit: [
                .bundleID("me.mhaeuser.BatteryToolkit"),
                .path("/Library/PrivilegedHelperTools/me.mhaeuser.batterytoolkitd"),
                .path("/Library/LaunchDaemons/me.mhaeuser.batterytoolkitd.plist"),
            ],
            .batt: [
                .path("/Library/LaunchDaemons/cc.chlc.batt.plist"),
                .path("/usr/local/bin/batt"),
                .path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist"),
                .path("/opt/homebrew/bin/batt"),
                .bundleID("cc.chlc.batt"),
            ],
            .bclm: [
                .path("/Library/LaunchDaemons/com.zackelia.bclm.plist"),
                .path("/usr/local/bin/bclm"),
                .path("/opt/homebrew/bin/bclm"),
                .path("/Library/LaunchDaemons/com.biscuitehh.bclm_persist.plist"),
            ],
        ]
        for tool in OtherChargeTool.allCases {
            #expect(tool.footprints == expected[tool], "\(tool.rawValue)")
        }
    }

    // MARK: - Clean Mac

    @Test func aCleanMacDetectsNothing() {
        #expect(detect().isEmpty)
    }

    // MARK: - Launch Services remembers deleted apps

    @Test func anAppInTheUserTrashIsIgnored() {
        let trashed = URL(fileURLWithPath: "\(home)/.Trash/AlDente.app")
        #expect(detect(paths: [trashed.path], apps: ["com.apphousekitchen.aldente-pro": [trashed]]).isEmpty)
    }

    @Test func anAppInAVolumeTrashIsIgnored() {
        let trashed = URL(fileURLWithPath: "/Volumes/Data/.Trashes/501/batt.app")
        #expect(detect(paths: [trashed.path], apps: ["cc.chlc.batt": [trashed]]).isEmpty)
    }

    @Test func anAppWhoseFileIsGoneIsIgnored() {
        let deleted = URL(fileURLWithPath: "/Applications/Battery Toolkit.app")
        #expect(detect(apps: ["me.mhaeuser.BatteryToolkit": [deleted]]).isEmpty)
    }

    /// Launch Services may list the trashed copy first; a live copy elsewhere still counts.
    @Test func aLiveCopyBesideATrashedOneIsDetected() {
        let trashed = URL(fileURLWithPath: "\(home)/.Trash/batt.app")
        let live = URL(fileURLWithPath: "/Applications/batt.app")
        let detected = detect(paths: [trashed.path, live.path], apps: ["cc.chlc.batt": [trashed, live]])
        #expect(detected == [DetectedChargeTool(tool: .batt, matchedFootprints: [.bundleID("cc.chlc.batt")], applications: [live])])
    }

    /// An app Launch Services knows from a mounted disk image — the one it was installed
    /// from, or one merely opened to look — is not installed on this Mac.
    @Test func anAppOnAMountedVolumeIsIgnored() {
        let mounted = URL(fileURLWithPath: "/Volumes/batt/batt.app")
        #expect(detect(paths: [mounted.path], apps: ["cc.chlc.batt": [mounted]]).isEmpty)
        let otherMounted = URL(fileURLWithPath: "/Volumes/AlDente Pro/AlDente.app")
        #expect(detect(paths: [otherMounted.path], apps: ["com.apphousekitchen.aldente-pro": [otherMounted]]).isEmpty)
    }

    // MARK: - Several at once

    @Test func severalToolsComeBackInStableOrderWithoutDuplicates() {
        let detected = detect(paths: [
            // Listed out of order, and with two footprints each for bclm and battery.
            "/opt/homebrew/bin/bclm",
            "/usr/local/bin/bclm",
            "/Library/LaunchDaemons/cc.chlc.batt.plist",
            "/usr/local/bin/battery",
            "\(home)/.battery/maintain.percentage",
        ])
        #expect(detected.map(\.tool) == [.batteryCLI, .batt, .bclm])
        // Every footprint that matched is kept, in table order; the first is the primary.
        #expect(detected[0].matchedFootprints == [.path("/usr/local/bin/battery"), .homeRelativePath(".battery/maintain.percentage")])
        #expect(detected[0].matchedFootprint == .path("/usr/local/bin/battery"))
        #expect(detected[2].matchedFootprints == [.path("/usr/local/bin/bclm"), .path("/opt/homebrew/bin/bclm")])
        #expect(detected[2].matchedFootprint == .path("/usr/local/bin/bclm"))
    }

    @Test func liveAppCopiesAreKeptForTheRemovalAdvice() {
        let live = URL(fileURLWithPath: "/Applications/Battery.app")
        let detected = detect(
            paths: [live.path, "/usr/local/bin/battery"],
            apps: ["co.palokaj.battery": [live]]
        )
        #expect(detected == [DetectedChargeTool(
            tool: .batteryCLI,
            matchedFootprints: [.path("/usr/local/bin/battery"), .bundleID("co.palokaj.battery")],
            applications: [live]
        )])
    }

    /// The log line: every footprint, then where each app copy is, with the home folder
    /// written as `~` so a customer's user name stays out of the log.
    @Test func theLogLineListsEveryFootprintWithTheHomeAbbreviated() {
        let detected = DetectedChargeTool(
            tool: .batt,
            matchedFootprints: [.path("/usr/local/bin/batt"), .bundleID("cc.chlc.batt")],
            applications: [URL(fileURLWithPath: "\(home)/Applications/batt.app")]
        )
        #expect(detected.logDescription(homeDirectory: home) == "batt (/usr/local/bin/batt, app cc.chlc.batt at ~/Applications/batt.app)")
        #expect(detected.description == "batt (/usr/local/bin/batt, app cc.chlc.batt)")
    }

    // MARK: - Home-relative paths

    @Test func homeRelativePathsResolveAgainstTheInjectedHome() {
        let plist = "Library/LaunchAgents/battery.plist"
        #expect(detect(paths: ["/Users/someoneelse/\(plist)"], home: "/Users/tester").isEmpty)
        #expect(detect(paths: ["/Users/someoneelse/\(plist)"], home: "/Users/someoneelse").map(\.tool) == [.batteryCLI])
        // A trailing slash on the home must not produce a double slash.
        #expect(detect(paths: ["/Users/someoneelse/\(plist)"], home: "/Users/someoneelse/").map(\.tool) == [.batteryCLI])
    }

    @Test func homeRelativeFootprintsRenderWithATilde() {
        #expect(OtherChargeToolFootprint.homeRelativePath(".battery/maintain.percentage").description == "~/.battery/maintain.percentage")
        #expect(OtherChargeToolFootprint.path("/usr/local/bin/batt").description == "/usr/local/bin/batt")
        #expect(OtherChargeToolFootprint.bundleID("cc.chlc.batt").description == "app cc.chlc.batt")
    }

    // MARK: - Names

    @Test func displayNames() {
        // Not "battery": opening a sentence, that reads as the user's own battery.
        #expect(OtherChargeTool.batteryCLI.displayName == "battery CLI")
        #expect(OtherChargeTool.alDente.displayName == "AlDente")
        #expect(OtherChargeTool.batteryToolkit.displayName == "Battery Toolkit")
        #expect(OtherChargeTool.batt.displayName == "batt")
        #expect(OtherChargeTool.bclm.displayName == "bclm")
    }

    // MARK: - Removal clears every footprint

    /// What each removal step takes off the Mac, written down from each tool's upstream
    /// documentation independently of the code that picks the steps. The advice is only
    /// right if, followed to the end, it leaves no footprint behind — otherwise the warning
    /// never goes away.
    static let commandRemoves: [String: Set<OtherChargeToolFootprint>] = [
        // battery.sh `uninstall`: the LaunchAgent, the binfolder and its symlink, the
        // sudoers entry and ~/.battery. Not the Electron app.
        "battery uninstall": [
            .homeRelativePath("Library/LaunchAgents/battery.plist"),
            .path("/usr/local/co.palokaj.battery"),
            .path("/usr/local/bin/battery"),
            .path("/private/etc/sudoers.d/battery"),
            .homeRelativePath(".battery/maintain.percentage"),
        ],
        // batt README, script install: `uninstall` removes the daemon, not the binary.
        "sudo batt uninstall": [.path("/Library/LaunchDaemons/cc.chlc.batt.plist")],
        "sudo rm /usr/local/bin/batt": [.path("/usr/local/bin/batt")],
        // batt README, Homebrew: `disable` only puts the limit back to 100%.
        "sudo batt disable": [],
        "sudo brew services stop batt": [.path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist")],
        "brew uninstall batt": [.path("/opt/homebrew/bin/batt")],
        // bclm: `unpersist` unloads and deletes its plist; the Makefile installs the
        // binary with `cp`, so `rm` removes it; the tap is a formula.
        "sudo bclm unpersist": [.path("/Library/LaunchDaemons/com.zackelia.bclm.plist")],
        "sudo rm /Library/LaunchDaemons/com.biscuitehh.bclm_persist.plist": [.path("/Library/LaunchDaemons/com.biscuitehh.bclm_persist.plist")],
        "sudo rm /usr/local/bin/bclm": [.path("/usr/local/bin/bclm")],
        "brew uninstall bclm": [.path("/opt/homebrew/bin/bclm")],
    ]

    /// Commands that remove nothing but must run first. Allowed only alongside the
    /// footprint they prepare for.
    static let preparatoryCommands: [String: OtherChargeToolFootprint] = [
        "sudo batt disable": .path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist"),
    ]

    static func removed(by step: OtherChargeToolRemovalStep, tool: OtherChargeTool) -> Set<OtherChargeToolFootprint> {
        switch step {
        case let .terminalCommands(commands):
            return commands.reduce(into: []) { removed, command in
                guard let effect = commandRemoves[command] else {
                    Issue.record("No known effect for `\(command)`")
                    return
                }
                removed.formUnion(effect)
            }
        case .inAppAlDente:
            // AlDente's Remove AlDente, every box checked, Delete Permanently: per the
            // vendor's guide it removes the helper and the app itself.
            return tool == .alDente ? Set(OtherChargeTool.alDente.footprints) : []
        case .inAppBatteryToolkit:
            // Remove the background service from inside the app, then delete the app.
            return tool == .batteryToolkit ? Set(OtherChargeTool.batteryToolkit.footprints) : []
        case .battAppUninstallDaemon:
            // batt.app's Uninstall Daemon… runs the same uninstall as `sudo batt uninstall`.
            return tool == .batt ? [.path("/Library/LaunchDaemons/cc.chlc.batt.plist")] : []
        case let .moveToTrash(appNames):
            // Trashing the app removes its bundle-ID footprint; a trashed app is ignored.
            guard !appNames.isEmpty else { return [] }
            return Set(tool.footprints.filter { if case .bundleID = $0 { true } else { false } })
        }
    }

    struct CombinationCase: CustomTestStringConvertible, Sendable {
        let tool: OtherChargeTool
        let matched: [OtherChargeToolFootprint]
        var testDescription: String { "\(tool.rawValue): \(matched.map(\.description).joined(separator: " + "))" }
    }

    /// Every non-empty combination of each tool's footprints, in table order.
    static let allCombinations: [CombinationCase] = OtherChargeTool.allCases.flatMap { tool in
        let footprints = tool.footprints
        return (1 ..< (1 << footprints.count)).map { mask in
            CombinationCase(tool: tool, matched: footprints.indices.filter { mask & (1 << $0) != 0 }.map { footprints[$0] })
        }
    }

    @Test(arguments: allCombinations)
    func followingTheAdviceRemovesEveryMatchedFootprint(_ testCase: CombinationCase) {
        let detected = DetectedChargeTool(tool: testCase.tool, matchedFootprints: testCase.matched)
        let steps = detected.removal
        #expect(!steps.isEmpty)
        let removed = steps.reduce(into: Set<OtherChargeToolFootprint>()) { $0.formUnion(Self.removed(by: $1, tool: testCase.tool)) }
        let left = testCase.matched.filter { !removed.contains($0) }
        #expect(left.isEmpty, "left behind: \(left)")
    }

    /// The other half: no command for something that is not there. A leftover binary gets
    /// one precise command, not the whole uninstall of a tool that is mostly gone.
    @Test(arguments: allCombinations)
    func everyCommandRemovesSomethingThatMatched(_ testCase: CombinationCase) {
        let matched = Set(testCase.matched)
        let detected = DetectedChargeTool(tool: testCase.tool, matchedFootprints: testCase.matched)
        for case let .terminalCommands(commands) in detected.removal {
            for command in commands {
                if let prepares = Self.preparatoryCommands[command] {
                    #expect(matched.contains(prepares), "`\(command)` without \(prepares)")
                } else {
                    #expect(!(Self.commandRemoves[command] ?? []).isDisjoint(with: matched), "`\(command)` removes nothing that matched")
                }
            }
        }
    }

    /// In-app steps need the app, so they come first; moving apps to the Trash comes last,
    /// after anything that needs them; Terminal commands are one step.
    @Test(arguments: allCombinations)
    func stepsComeInAnOrderThatCanBeFollowed(_ testCase: CombinationCase) {
        let steps = DetectedChargeTool(tool: testCase.tool, matchedFootprints: testCase.matched).removal
        func rank(_ step: OtherChargeToolRemovalStep) -> Int {
            switch step {
            case .inAppAlDente, .inAppBatteryToolkit, .battAppUninstallDaemon: 0
            case .terminalCommands: 1
            case .moveToTrash: 2
            }
        }
        #expect(steps.map(rank) == steps.map(rank).sorted())
        #expect(Set(steps.map(rank)).count == steps.count, "one step of each kind at most")
    }

    @Test func removalAdviceForRepresentativeInstalls() {
        func removal(_ tool: OtherChargeTool, _ footprints: [OtherChargeToolFootprint], apps: [URL] = []) -> [OtherChargeToolRemovalStep] {
            DetectedChargeTool(tool: tool, matchedFootprints: footprints, applications: apps).removal
        }
        // battery CLI alone, then with its Electron app, then the app alone.
        #expect(removal(.batteryCLI, [.path("/usr/local/bin/battery")]) == [.terminalCommands(["battery uninstall"])])
        #expect(removal(
            .batteryCLI,
            [.path("/usr/local/bin/battery"), .bundleID("co.palokaj.battery")],
            apps: [URL(fileURLWithPath: "/Applications/Battery.app")]
        ) == [.terminalCommands(["battery uninstall"]), .moveToTrash(["Battery.app"])])
        #expect(removal(.batteryCLI, [.bundleID("co.palokaj.battery")]) == [.moveToTrash(["Battery.app"])])
        // The app's name is the one on disk, when it was found.
        #expect(removal(
            .batteryCLI,
            [.bundleID("co.palokaj.battery")],
            apps: [URL(fileURLWithPath: "/Applications/Battery 2.app")]
        ) == [.moveToTrash(["Battery 2.app"])])

        #expect(removal(.alDente, [.bundleID("com.davidwernhart.AlDente")]) == [.inAppAlDente])
        #expect(removal(.batteryToolkit, [.bundleID("me.mhaeuser.BatteryToolkit")]) == [.inAppBatteryToolkit])

        // batt, script install: the uninstaller leaves the binary.
        #expect(removal(.batt, [.path("/Library/LaunchDaemons/cc.chlc.batt.plist"), .path("/usr/local/bin/batt")])
            == [.terminalCommands(["sudo batt uninstall", "sudo rm /usr/local/bin/batt"])])
        #expect(removal(.batt, [.path("/usr/local/bin/batt")]) == [.terminalCommands(["sudo rm /usr/local/bin/batt"])])
        // batt, Homebrew.
        #expect(removal(.batt, [.path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist"), .path("/opt/homebrew/bin/batt")])
            == [.terminalCommands(["sudo batt disable", "sudo brew services stop batt", "brew uninstall batt"])])
        #expect(removal(.batt, [.path("/opt/homebrew/bin/batt")]) == [.terminalCommands(["brew uninstall batt"])])
        // batt.app, with the daemon it installed.
        #expect(removal(
            .batt,
            [.path("/Library/LaunchDaemons/cc.chlc.batt.plist"), .path("/usr/local/bin/batt"), .bundleID("cc.chlc.batt")],
            apps: [URL(fileURLWithPath: "/Applications/batt.app")]
        ) == [.battAppUninstallDaemon(appName: "batt.app"), .terminalCommands(["sudo rm /usr/local/bin/batt"]), .moveToTrash(["batt.app"])])
        #expect(removal(.batt, [.bundleID("cc.chlc.batt")]) == [.battAppUninstallDaemon(appName: "batt.app"), .moveToTrash(["batt.app"])])

        // bclm: unpersist, then the binary by how it was installed.
        #expect(removal(.bclm, [.path("/Library/LaunchDaemons/com.zackelia.bclm.plist"), .path("/usr/local/bin/bclm")])
            == [.terminalCommands(["sudo bclm unpersist", "sudo rm /usr/local/bin/bclm"])])
        #expect(removal(.bclm, [.path("/Library/LaunchDaemons/com.zackelia.bclm.plist"), .path("/opt/homebrew/bin/bclm")])
            == [.terminalCommands(["sudo bclm unpersist", "brew uninstall bclm"])])
        #expect(removal(.bclm, [.path("/usr/local/bin/bclm")]) == [.terminalCommands(["sudo rm /usr/local/bin/bclm"])])
        #expect(removal(.bclm, [.path("/opt/homebrew/bin/bclm")]) == [.terminalCommands(["brew uninstall bclm"])])
    }

    // MARK: - Wording rule

    @Test func theBatteryCLIOnlyFightsOverTheLightAndDischargeOnMacOS27Firmware() {
        let expected: [ChargeBackend?: OtherChargeToolContention] = [
            .systemChargeLimit: .magSafeLightAndForceDischarge,
            .firmwareRange: .magSafeLightAndForceDischarge,
            .chte: .chargeLimit,
            .legacyCH0BC: .chargeLimit,
            .unsupported: .chargeLimit,
            nil: .chargeLimit,
        ]
        #expect(Set(expected.keys.compactMap { $0 }) == Set(ChargeBackend.allCases))
        for (backend, contention) in expected {
            #expect(OtherChargeTool.batteryCLI.contention(backend: backend) == contention, "\(String(describing: backend))")
        }
    }

    @Test func everyOtherToolFightsOverTheChargeLimitOnEveryBackend() {
        let backends: [ChargeBackend?] = ChargeBackend.allCases + [nil]
        for tool in OtherChargeTool.allCases where tool != .batteryCLI {
            for backend in backends {
                #expect(tool.contention(backend: backend) == .chargeLimit, "\(tool.rawValue) \(String(describing: backend))")
            }
        }
    }

    @Test func rawValuesAreStable() {
        #expect(OtherChargeTool.allCases.map(\.rawValue) == ["battery", "aldente", "batteryToolkit", "batt", "bclm"])
    }
}
