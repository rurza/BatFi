//
//  SlowedAppsTests.swift
//  BatFi
//
//  Unit tests for the edits the menu's tortoise and the Energy pane make to the apps slowed
//  down on battery.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SlowedAppsTests {
    private let slack = "com.tinyspeck.slackmacgap"
    private let xcode = "com.apple.dt.Xcode"
    private let safari = "com.apple.Safari"

    // MARK: - The tortoise

    @Test func theTortoiseAddsAnAppToBeSlowedOnlyWhileItIsInTheBackground() {
        #expect(SlowedApps.toggling(slack, in: [:]) == [slack: .backgroundOnly])
    }

    @Test(arguments: [SlowDownMode.backgroundOnly, .always])
    func theTortoiseRemovesAnAppAlreadyInTheListWhateverItsMode(mode: SlowDownMode) {
        #expect(SlowedApps.toggling(slack, in: [slack: mode]).isEmpty)
    }

    @Test func theTortoiseLeavesTheOtherAppsAsTheyWere() {
        let apps: [String: SlowDownMode] = [xcode: .always, safari: .backgroundOnly]

        #expect(SlowedApps.toggling(slack, in: apps) == [xcode: .always, safari: .backgroundOnly, slack: .backgroundOnly])
        #expect(SlowedApps.toggling(xcode, in: apps) == [safari: .backgroundOnly])
    }

    // MARK: - Add App…

    @Test func anAddedAppIsSlowedOnlyWhileItIsInTheBackground() {
        #expect(SlowedApps.adding([slack, safari], to: [:]) == [slack: .backgroundOnly, safari: .backgroundOnly])
    }

    /// Adding again what is already there is not a request to reset how it is slowed.
    @Test func addingAnAppAlreadyInTheListKeepsItsMode() {
        #expect(SlowedApps.adding([xcode, slack], to: [xcode: .always]) == [xcode: .always, slack: .backgroundOnly])
    }

    // MARK: - Remove

    @Test func removingAnAppLeavesTheOthers() {
        #expect(SlowedApps.removing(slack, from: [slack: .always, safari: .backgroundOnly]) == [safari: .backgroundOnly])
    }

    @Test func removingAnAppThatIsNotInTheListChangesNothing() {
        #expect(SlowedApps.removing(slack, from: [safari: .always]) == [safari: .always])
    }

    // MARK: - The mode picker

    @Test func choosingAModeChangesThatAppOnly() {
        let apps: [String: SlowDownMode] = [slack: .backgroundOnly, safari: .backgroundOnly]

        #expect(SlowedApps.setting(.always, for: slack, in: apps) == [slack: .always, safari: .backgroundOnly])
        #expect(SlowedApps.setting(.backgroundOnly, for: slack, in: [slack: .always]) == [slack: .backgroundOnly])
    }

    /// The tortoise in the menu may have taken the app out while its picker was on screen:
    /// picking a mode then must not bring it back.
    @Test func choosingAModeForAnAppNoLongerInTheListDoesNotAddItBack() {
        #expect(SlowedApps.setting(.always, for: slack, in: [safari: .backgroundOnly]) == [safari: .backgroundOnly])
    }

    // MARK: - The "Always" warning

    @Test func theAlwaysWarningAppliesOnlyWhileSomeAppIsSlowedAlways() {
        #expect(!SlowedApps.usesAlways([:]))
        #expect(!SlowedApps.usesAlways([slack: .backgroundOnly, safari: .backgroundOnly]))
        #expect(SlowedApps.usesAlways([slack: .backgroundOnly, xcode: .always]))
    }
}
