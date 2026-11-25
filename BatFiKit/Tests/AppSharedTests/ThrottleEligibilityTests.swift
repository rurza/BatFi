//
//  ThrottleEligibilityTests.swift
//  BatFi
//
//  Unit tests for which apps in the high-energy list get "Slow down on battery" and Quit.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ThrottleEligibilityTests {
    private let ownBundleIDs: Set<String> = ["software.micropixels.BatFi", "software.micropixels.BatFi.beta"]

    private func canOffer(_ bundleID: String?, at path: String?) -> Bool {
        ThrottleEligibility.canOfferActions(
            bundleID: bundleID,
            bundleURL: path.map { URL(fileURLWithPath: $0, isDirectory: true) },
            ownBundleIDs: ownBundleIDs
        )
    }

    @Test func anAppInApplicationsIsOffered() {
        #expect(canOffer("com.tinyspeck.slackmacgap", at: "/Applications/Slack.app"))
    }

    /// Apple's own apps live under `/System/Applications` and are ordinary apps: Music, Mail
    /// and Safari are exactly the kind people want to slow down.
    @Test func anAppInSystemApplicationsIsOffered() {
        #expect(canOffer("com.apple.Music", at: "/System/Applications/Music.app"))
    }

    @Test func finderIsNotOffered() {
        #expect(!canOffer("com.apple.finder", at: "/System/Library/CoreServices/Finder.app"))
    }

    /// The location alone rules it out: parts of macOS that are not on the denylist.
    @Test(arguments: [
        "/System/Library/CoreServices/Siri.app",
        "/Library/Apple/System/Library/CoreServices/XProtect.app",
        "/usr/libexec/SomeAgent.app",
    ])
    func somethingThatShipsAsPartOfMacOSIsNotOffered(path: String) {
        #expect(!canOffer("com.example.system-part", at: path))
    }

    /// Wherever they are installed: these draw the desktop, the Dock and the menu bar.
    @Test(arguments: [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.Spotlight",
    ])
    func aDenylistedAppIsNotOffered(bundleID: String) {
        #expect(!canOffer(bundleID, at: "/Applications/Copy.app"))
    }

    @Test(arguments: ["software.micropixels.BatFi", "software.micropixels.BatFi.beta"])
    func batFiItselfIsNotOffered(bundleID: String) {
        #expect(!canOffer(bundleID, at: "/Applications/BatFi.app"))
    }

    /// What the high-energy list shows when macOS withholds the name.
    @Test(arguments: ["<private>", "REDACTED", "", "  "])
    func aRedactedOrMissingBundleIDIsNotOffered(bundleID: String) {
        #expect(!canOffer(bundleID, at: "/Applications/Slack.app"))
    }

    @Test func noBundleIDIsNotOffered() {
        #expect(!canOffer(nil, at: "/Applications/Slack.app"))
    }

    @Test func noBundleLocationIsNotOffered() {
        #expect(!canOffer("com.tinyspeck.slackmacgap", at: nil))
    }

    // MARK: - Quit

    /// Whatever its activation policy: a menu bar app such as Dropbox quits like any other.
    @Test(arguments: [(true, true, true), (true, false, false), (false, true, false), (false, false, false)])
    func quitIsOfferedForAnEligibleAppThatIsRunning(eligible: Bool, isRunning: Bool, offered: Bool) {
        #expect(ThrottleEligibility.canQuit(eligible: eligible, isRunning: isRunning) == offered)
    }

    // MARK: - The tortoise

    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func anIneligibleAppIsNeverSlowedDown(isRunning: Bool, isRegular: Bool) {
        #expect(!ThrottleEligibility.canSlowDown(
            eligible: false,
            isRunning: isRunning,
            isRegular: isRegular,
            declaresNoDockIcon: false
        ))
    }

    /// Only an app with a Dock icon can come to the front, and so be given back when the user
    /// turns to it: a menu bar app slowed "in the background" would be slowed for good.
    @Test func aRunningAppIsSlowedDownOnlyWhileItHasADockIcon() {
        #expect(ThrottleEligibility.canSlowDown(eligible: true, isRunning: true, isRegular: true, declaresNoDockIcon: false))
        #expect(!ThrottleEligibility.canSlowDown(eligible: true, isRunning: true, isRegular: false, declaresNoDockIcon: false))
    }

    /// What the running app does wins over what its bundle declares: some apps that declare
    /// no Dock icon show one while a window is open.
    @Test func aRunningAppWithADockIconIsSlowedDownWhateverItsBundleDeclares() {
        #expect(ThrottleEligibility.canSlowDown(eligible: true, isRunning: true, isRegular: true, declaresNoDockIcon: true))
    }

    @Test(arguments: [(false, true), (true, false)])
    func anAppNotRunningIsSlowedDownUnlessItsBundleDeclaresNoDockIcon(declaresNoDockIcon: Bool, offered: Bool) {
        #expect(ThrottleEligibility.canSlowDown(
            eligible: true,
            isRunning: false,
            isRegular: false,
            declaresNoDockIcon: declaresNoDockIcon
        ) == offered)
    }

    // MARK: - What a bundle declares

    @Test(arguments: ["LSUIElement", "LSBackgroundOnly"])
    func aBundleDeclaringItselfAMenuBarOrBackgroundAppHasNoDockIcon(key: String) {
        let yes: [Any] = [true, NSNumber(value: true), NSNumber(value: 1), 1, "1", "YES", "yes", "true", "TRUE"]
        for value in yes {
            #expect(ThrottleEligibility.declaresNoDockIcon([key: value]), "\(key) = \(value)")
        }
    }

    @Test(arguments: ["LSUIElement", "LSBackgroundOnly"])
    func aBundleDeclaringTheKeyFalseHasADockIcon(key: String) {
        let no: [Any] = [false, NSNumber(value: false), NSNumber(value: 0), 0, "0", "NO", "false", "", "maybe"]
        for value in no {
            #expect(!ThrottleEligibility.declaresNoDockIcon([key: value]), "\(key) = \(value)")
        }
    }

    @Test func aBundleDeclaringNeitherKeyHasADockIcon() {
        #expect(!ThrottleEligibility.declaresNoDockIcon(nil))
        #expect(!ThrottleEligibility.declaresNoDockIcon([:]))
        #expect(!ThrottleEligibility.declaresNoDockIcon(["CFBundleName": "Slack", "LSMinimumSystemVersion": "11.0"]))
    }

    // MARK: - Add App…

    @Test func anEligibleAppWithADockIconCanBeAdded() {
        #expect(ThrottleEligibility.addRefusal(eligible: true, declaresNoDockIcon: false) == nil)
    }

    /// Being part of macOS, or BatFi, is the reason given, whatever the bundle declares.
    @Test(arguments: [false, true])
    func anIneligibleAppIsRefusedAsSuch(declaresNoDockIcon: Bool) {
        #expect(ThrottleEligibility.addRefusal(eligible: false, declaresNoDockIcon: declaresNoDockIcon) == .notEligible)
    }

    @Test func anEligibleAppWithoutADockIconIsRefusedForThat() {
        #expect(ThrottleEligibility.addRefusal(eligible: true, declaresNoDockIcon: true) == .noDockIcon)
    }
}
