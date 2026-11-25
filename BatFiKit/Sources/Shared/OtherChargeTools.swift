//
//  OtherChargeTools.swift
//
//
//  Other charge-control tools installed on this Mac. They write the same SMC keys BatFi
//  does, so with one of them running BatFi's limit, light or discharge can be undone behind
//  its back — and only the user can remove them.
//
//  Detected by install footprint alone: whether a file exists, and whether Launch Services
//  knows an app by its bundle ID. No root, no process scan, no file contents. A footprint
//  says the tool is *installed*, not that it is running right now; that is the honest
//  claim, and the one the user can act on.
//
//  Footprints were checked against each tool's upstream source where it is open
//  (2026-10-16). AlDente Pro is closed source; its entries come from Fleet's software
//  catalog only.
//

import Foundation

/// A charge-control tool that fights BatFi over the SMC.
///
/// Raw values are stable: they are what gets logged and may be persisted.
public enum OtherChargeTool: String, Sendable, CaseIterable, Hashable {
    /// actuallymentor/battery, the CLI, and the Electron app that installs it.
    case batteryCLI = "battery"
    /// AlDente Pro, and the legacy free AlDente.
    case alDente = "aldente"
    /// mhaeuser/Battery-Toolkit.
    case batteryToolkit = "batteryToolkit"
    /// charlie0129/batt, script or Homebrew install, and its GUI.
    case batt = "batt"
    /// zackelia/bclm.
    case bclm = "bclm"

    /// The tool's own name. Product names, so not localized.
    public var displayName: String {
        switch self {
        // Not "battery": opening a sentence, that reads as the user's own battery.
        case .batteryCLI: "battery CLI"
        case .alDente: "AlDente"
        case .batteryToolkit: "Battery Toolkit"
        case .batt: "batt"
        case .bclm: "bclm"
        }
    }

    /// Every footprint that marks this tool as installed, in the order they are reported:
    /// when several match, all are kept, and the first one here is the primary.
    public var footprints: [OtherChargeToolFootprint] {
        switch self {
        case .batteryCLI:
            [
                .homeRelativePath("Library/LaunchAgents/battery.plist"),
                // The current binfolder; holds `battery` and `smc`.
                .path("/usr/local/co.palokaj.battery"),
                // A symlink into the folder above, or a plain binary on older installs.
                .path("/usr/local/bin/battery"),
                // The folder is 755, so a non-root stat works.
                .path("/private/etc/sudoers.d/battery"),
                .homeRelativePath(".battery/maintain.percentage"),
                // The Electron GUI, which installs the CLI.
                .bundleID("co.palokaj.battery"),
            ]
        case .alDente:
            [
                // Pro — closed source; from Fleet's software catalog, not verified upstream.
                .bundleID("com.apphousekitchen.aldente-pro"),
                .path("/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper"),
                .path("/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist"),
                // Legacy free AlDente — verified against its open repository.
                .bundleID("com.davidwernhart.AlDente"),
                .path("/Library/PrivilegedHelperTools/com.davidwernhart.Helper"),
                .path("/Library/LaunchDaemons/com.davidwernhart.Helper.plist"),
            ]
        case .batteryToolkit:
            [
                // Mixed case, as upstream spells it. Current installs register their daemon
                // through SMAppService from inside the app and leave no file in
                // /Library/LaunchDaemons, so the app is the footprint that matters.
                .bundleID("me.mhaeuser.BatteryToolkit"),
                // Legacy helper installs.
                .path("/Library/PrivilegedHelperTools/me.mhaeuser.batterytoolkitd"),
                .path("/Library/LaunchDaemons/me.mhaeuser.batterytoolkitd.plist"),
            ]
        case .batt:
            [
                // Script install.
                .path("/Library/LaunchDaemons/cc.chlc.batt.plist"),
                .path("/usr/local/bin/batt"),
                // Homebrew (v0.7.5+).
                .path("/Library/LaunchDaemons/homebrew.mxcl.batt.plist"),
                .path("/opt/homebrew/bin/batt"),
                // batt.app.
                .bundleID("cc.chlc.batt"),
            ]
        case .bclm:
            [
                // The persist plist in every upstream commit since 2020.
                .path("/Library/LaunchDaemons/com.zackelia.bclm.plist"),
                // Makefile install, then the Homebrew tap.
                .path("/usr/local/bin/bclm"),
                .path("/opt/homebrew/bin/bclm"),
                // Never appears upstream; kept as an unverified extra footprint only.
                .path("/Library/LaunchDaemons/com.biscuitehh.bclm_persist.plist"),
            ]
        }
    }

    /// What this tool fights BatFi over on a Mac whose charge backend is `backend` — nil
    /// when the backend is not known yet.
    ///
    /// Every tool fights over the charge limit itself, with one exception. On macOS 27-era
    /// firmware (`.firmwareRange`, or the `.systemChargeLimit` fallback it resolves to)
    /// both `CHTE` and `CH0B` are gone, so the battery CLI has no working charge-inhibit
    /// key left. It still writes `ACLC` every 60 seconds, which overrides BatFi's MagSafe
    /// light, and it clears `CHIE`, which ends BatFi's forced discharge. Telling that user
    /// their limit is under attack would be false; telling them nothing would leave the
    /// light and "Run on Battery" broken with no explanation.
    ///
    /// An unknown backend answers `.chargeLimit`: the claim that holds on every firmware
    /// the CLI can still inhibit on, and the more cautious one to make.
    public func contention(backend: ChargeBackend?) -> OtherChargeToolContention {
        guard self == .batteryCLI else { return .chargeLimit }
        switch backend {
        case .systemChargeLimit, .firmwareRange:
            return .magSafeLightAndForceDischarge
        case .chte, .legacyCH0BC, .unsupported, nil:
            return .chargeLimit
        }
    }
}

/// What another tool fights BatFi over. See `OtherChargeTool.contention(backend:)`.
public enum OtherChargeToolContention: Sendable, Hashable {
    /// It writes the charge limit or inhibit, so BatFi's limit may not be the one in force.
    case chargeLimit
    /// It only overrides the MagSafe light and ends forced discharge.
    case magSafeLightAndForceDischarge
}

/// One sign that a tool is installed.
public enum OtherChargeToolFootprint: Sendable, Hashable, CustomStringConvertible {
    /// An absolute path.
    case path(String)
    /// A path relative to the user's home directory, without a leading slash.
    case homeRelativePath(String)
    /// An application bundle identifier, looked up through Launch Services.
    case bundleID(String)

    /// The footprint as it appears in diagnostics. Not localized: it is log text.
    public var description: String {
        switch self {
        case let .path(path): path
        case let .homeRelativePath(relative): "~/\(relative)"
        case let .bundleID(bundleID): "app \(bundleID)"
        }
    }
}

/// One step of removing a tool. Data only — the UI turns it into localized text.
///
/// A tool's steps come in this order, at most one of each kind: an in-app removal (it needs
/// the app), then Terminal commands, then moving apps to the Trash (after anything that
/// needs them).
public enum OtherChargeToolRemovalStep: Sendable, Hashable {
    /// AlDente Settings → Remove AlDente, which removes its helper and the app itself.
    case inAppAlDente
    /// Battery Toolkit: remove its background service from inside the app, then delete it.
    case inAppBatteryToolkit
    /// batt.app's own Uninstall Daemon…, which does what `sudo batt uninstall` does. The
    /// app's file name ("batt.app").
    case battAppUninstallDaemon(appName: String)
    /// Commands to run in Terminal, in order.
    case terminalCommands([String])
    /// App bundles to move to the Trash, by file name ("Battery.app").
    case moveToTrash([String])
}

/// A tool found on this Mac, with every one of its footprints that matched.
public struct DetectedChargeTool: Sendable, Hashable, CustomStringConvertible {
    public let tool: OtherChargeTool
    /// Every footprint that matched, in `OtherChargeTool.footprints` order. Never empty.
    public let matchedFootprints: [OtherChargeToolFootprint]
    /// Where the live copies of the tool's app are, when a bundle-ID footprint matched.
    /// Names the app in the removal advice; empty when the app was not found.
    public let applications: [URL]

    public init(tool: OtherChargeTool, matchedFootprints: [OtherChargeToolFootprint], applications: [URL] = []) {
        precondition(!matchedFootprints.isEmpty, "A detected tool has at least one footprint")
        self.tool = tool
        self.matchedFootprints = matchedFootprints
        self.applications = applications
    }

    public init(tool: OtherChargeTool, matchedFootprint: OtherChargeToolFootprint) {
        self.init(tool: tool, matchedFootprints: [matchedFootprint])
    }

    /// The first footprint that matched, in table order.
    public var matchedFootprint: OtherChargeToolFootprint { matchedFootprints[0] }

    /// How to remove it: steps that, followed to the end, take away every matched
    /// footprint — otherwise the warning would never go away. Only what matched gets a
    /// step, so a leftover binary gets one precise command rather than the uninstall of a
    /// tool that is mostly gone.
    public var removal: [OtherChargeToolRemovalStep] {
        let matched = Set(matchedFootprints)
        func has(_ path: String) -> Bool { matched.contains(.path(path)) }
        let hasApp = matched.contains { if case .bundleID = $0 { true } else { false } }
        let trash: [OtherChargeToolRemovalStep] = hasApp ? [.moveToTrash(appNames)] : []

        switch tool {
        case .alDente:
            // Remove AlDente, with every box checked, removes the app as well.
            return [.inAppAlDente]
        case .batteryToolkit:
            return [.inAppBatteryToolkit]
        case .batteryCLI:
            // `battery uninstall` removes every CLI piece, but not the Electron app.
            let cliMatched = matched.contains { if case .bundleID = $0 { false } else { true } }
            return (cliMatched ? [.terminalCommands(["battery uninstall"])] : []) + trash
        case .batt:
            var commands: [String] = []
            // batt.app's in-app uninstall stands in for `sudo batt uninstall`.
            if has("/Library/LaunchDaemons/cc.chlc.batt.plist"), !hasApp {
                commands.append("sudo batt uninstall")
            }
            // Homebrew: put the limit back first, then stop the service, then the formula.
            if has("/Library/LaunchDaemons/homebrew.mxcl.batt.plist") {
                commands += ["sudo batt disable", "sudo brew services stop batt"]
            }
            // The script's uninstaller leaves its binary behind.
            if has("/usr/local/bin/batt") {
                commands.append("sudo rm /usr/local/bin/batt")
            }
            // Only with the binary there: without it the formula is already gone.
            if has("/opt/homebrew/bin/batt") {
                commands.append("brew uninstall batt")
            }
            let inApp: [OtherChargeToolRemovalStep] = hasApp ? [.battAppUninstallDaemon(appName: appNames[0])] : []
            return inApp + (commands.isEmpty ? [] : [.terminalCommands(commands)]) + trash
        case .bclm:
            var commands: [String] = []
            // `unpersist` first: it needs the binary the next commands delete.
            if has("/Library/LaunchDaemons/com.zackelia.bclm.plist") {
                commands.append("sudo bclm unpersist")
            }
            if has("/Library/LaunchDaemons/com.biscuitehh.bclm_persist.plist") {
                commands.append("sudo rm /Library/LaunchDaemons/com.biscuitehh.bclm_persist.plist")
            }
            // The Makefile copies the binary in; the tap installs a formula.
            if has("/usr/local/bin/bclm") {
                commands.append("sudo rm /usr/local/bin/bclm")
            }
            if has("/opt/homebrew/bin/bclm") {
                commands.append("brew uninstall bclm")
            }
            return [.terminalCommands(commands)]
        }
    }

    /// The app's file names as found on disk, or the name it installs under when it was not
    /// located (a value built without a scan).
    private var appNames: [String] {
        var seen = Set<String>()
        let found = applications.map(\.lastPathComponent).filter { seen.insert($0).inserted }
        if !found.isEmpty { return found }
        switch tool {
        case .batteryCLI: return ["Battery.app"]
        case .batt: return ["batt.app"]
        case .alDente: return ["AlDente.app"]
        case .batteryToolkit: return ["Battery Toolkit.app"]
        case .bclm: return []
        }
    }

    /// "batt (/usr/local/bin/batt, app cc.chlc.batt)". Log text, not localized.
    public var description: String {
        "\(tool.displayName) (\(matchedFootprints.map(\.description).joined(separator: ", ")))"
    }

    /// The description, with where each app copy is: "batt (/usr/local/bin/batt, app
    /// cc.chlc.batt at ~/Applications/batt.app)". Paths under `homeDirectory` are written
    /// with `~`, so the user's name stays out of logs.
    public func logDescription(homeDirectory: String) -> String {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        func abbreviated(_ path: String) -> String {
            path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }
        var footprints = matchedFootprints.map(\.description)
        if !applications.isEmpty, let index = matchedFootprints.firstIndex(where: { if case .bundleID = $0 { true } else { false } }) {
            footprints[index] += " at " + applications.map { abbreviated($0.path) }.joined(separator: ", ")
        }
        return "\(tool.displayName) (\(footprints.joined(separator: ", ")))"
    }
}

public enum OtherChargeToolDetection {
    /// The tools installed on this Mac, in `OtherChargeTool.allCases` order, each once,
    /// with every one of its footprints that matched.
    ///
    /// - Parameters:
    ///   - homeDirectory: The user's real home, which `homeRelativePath` footprints
    ///     resolve against.
    ///   - fileExists: Whether anything exists at an absolute path.
    ///   - applicationURLs: Launch Services' answer for a bundle identifier.
    ///
    /// Launch Services remembers apps that have been deleted, and apps it has seen on a
    /// mounted disk image: an app URL counts only while its file still exists, it is not
    /// inside a Trash folder, and it is not under /Volumes. A Trash is where an uninstalled
    /// app sits until the user empties it; a disk image is where an app is installed
    /// *from*. Neither is an app installed on this Mac.
    public static func detect(
        homeDirectory: String,
        fileExists: (String) -> Bool,
        applicationURLs: (String) -> [URL]
    ) -> [DetectedChargeTool] {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return OtherChargeTool.allCases.compactMap { tool in
            var matched: [OtherChargeToolFootprint] = []
            var applications: [URL] = []
            for footprint in tool.footprints {
                switch footprint {
                case let .path(path):
                    if fileExists(path) { matched.append(footprint) }
                case let .homeRelativePath(relative):
                    if fileExists("\(home)/\(relative)") { matched.append(footprint) }
                case let .bundleID(bundleID):
                    let live = applicationURLs(bundleID).filter { isLiveApplication($0, fileExists: fileExists) }
                    if !live.isEmpty {
                        matched.append(footprint)
                        applications += live.filter { !applications.contains($0) }
                    }
                }
            }
            return matched.isEmpty ? nil : DetectedChargeTool(tool: tool, matchedFootprints: matched, applications: applications)
        }
    }

    static func isLiveApplication(_ url: URL, fileExists: (String) -> Bool) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard !components.contains(".Trash"), !components.contains(".Trashes") else { return false }
        guard components.count < 2 || components[1] != "Volumes" else { return false }
        return fileExists(url.path)
    }
}
