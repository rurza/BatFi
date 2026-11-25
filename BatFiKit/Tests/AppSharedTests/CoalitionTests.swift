//
//  CoalitionTests.swift
//  BatFi
//
//  Unit tests for when one report of the high-energy list is the same as the last. The list
//  is read every three seconds, and each report that differs is published to the menu and
//  logged, so "the same" has to mean what the row shows and acts on.
//

import AppKit
import Foundation
import Testing

@testable import AppShared

@Suite struct CoalitionTests {
    private let slack = "com.tinyspeck.slackmacgap"
    private let slackURL = URL(fileURLWithPath: "/Applications/Slack.app", isDirectory: true)

    private func coalition(
        _ bundleID: String? = nil,
        energyImpact: Double = 500,
        icon: NSImage? = nil,
        displayName: String? = "Slack",
        bundleURL: URL? = nil,
        isRunning: Bool = true,
        canOfferActions: Bool = true,
        canSlowDown: Bool = true
    ) -> Coalition {
        Coalition(
            bundleIdentifier: bundleID ?? slack,
            energyImpact: energyImpact,
            icon: icon,
            displayName: displayName,
            bundleURL: bundleURL ?? slackURL,
            isRunning: isRunning,
            canOfferActions: canOfferActions,
            canSlowDown: canSlowDown
        )
    }

    /// Each report looks the icon up again, and gets a new image object for the same icon —
    /// measured: `NSWorkspace.icon(forFile:)` answers a new `NSImage` every call, and two of
    /// them are not `isEqual`. Compared by the image, no report would ever match the last.
    @Test func theSameAppWithANewIconObjectIsTheSame() {
        let first = coalition(icon: NSImage(size: NSSize(width: 32, height: 32)))
        let second = coalition(icon: NSImage(size: NSSize(width: 32, height: 32)))

        #expect(first == second)
        #expect(TopCoalitionInfo(topCoalitions: [first]) == TopCoalitionInfo(topCoalitions: [second]))
    }

    /// The row shows a gauge, not the number: a move within one level changes nothing on
    /// screen.
    @Test func anEnergyImpactThatStaysWithinItsLevelIsTheSame() {
        #expect(coalition(energyImpact: 310) == coalition(energyImpact: 880))
    }

    @Test func anEnergyImpactThatCrossesALevelIsAChange() {
        #expect(coalition(energyImpact: 880) != coalition(energyImpact: 920))
    }

    @Test func everythingTheRowShowsOrActsOnIsAChange() {
        let base = coalition()
        #expect(base != coalition("com.apple.Safari"))
        #expect(base != coalition(displayName: "Slack Beta"))
        #expect(base != coalition(bundleURL: URL(fileURLWithPath: "/Users/me/Applications/Slack.app", isDirectory: true)))
        #expect(base != coalition(isRunning: false))
        #expect(base != coalition(canOfferActions: false))
        #expect(base != coalition(canSlowDown: false))
    }

    @Test func slowableAppsTakeTheLimitedSlotsBeforeOtherEnergyUsers() {
        let system = coalition("com.apple.system", energyImpact: 2000, canOfferActions: false, canSlowDown: false)
        let firstApp = coalition("com.example.first", energyImpact: 900)
        let menuBarApp = coalition("com.example.menu", energyImpact: 800, canSlowDown: false)
        let secondApp = coalition("com.example.second", energyImpact: 500)
        let report = TopCoalitionInfo(topCoalitions: [system, firstApp, menuBarApp, secondApp])

        #expect(report.prioritizingSlowable(capacity: 3).topCoalitions.map(\.bundleIdentifier) == [
            "com.example.first", "com.example.second", "com.apple.system",
        ])
        #expect(report.prioritizingSlowable(capacity: 1).topCoalitions.map(\.bundleIdentifier) == ["com.example.first"])
    }

    // MARK: - Apps that have quit

    /// The report covers a trailing window, so an app that quit a minute ago is still in it.
    @Test func anAppThatHasQuitIsNotListed() {
        let report = TopCoalitionInfo(topCoalitions: [
            coalition("com.example.quit", isRunning: false),
            coalition("com.example.running"),
        ])

        #expect(report.droppingQuitApps().topCoalitions.map(\.bundleIdentifier) == ["com.example.running"])
    }

    @Test func aRunningAppIsListed() {
        let report = TopCoalitionInfo(topCoalitions: [coalition()])

        #expect(report.droppingQuitApps() == report)
    }

    /// Nothing tells whether a daemon or a system coalition is still alive, so it stays.
    @Test func anEntryThatIsNotAnAppIsListedEvenThoughNothingRunsUnderItsName() {
        let daemon = Coalition(
            bundleIdentifier: "<private>",
            energyImpact: 500,
            icon: nil,
            displayName: nil,
            bundleURL: nil,
            isRunning: false,
            canOfferActions: false,
            canSlowDown: false
        )
        let report = TopCoalitionInfo(topCoalitions: [daemon])

        #expect(report.droppingQuitApps() == report)
    }

    /// Dropped before the list is cut to size: the next live entry takes the quit app's slot.
    @Test func anAppThatHasQuitLeavesItsSlotToTheNextEntry() {
        let report = TopCoalitionInfo(topCoalitions: [
            coalition("com.example.quit", energyImpact: 900, isRunning: false),
            coalition("com.example.first", energyImpact: 800),
            coalition("com.example.second", energyImpact: 500),
        ])

        #expect(report.droppingQuitApps().prioritizingSlowable(capacity: 2).topCoalitions.map(\.bundleIdentifier) == [
            "com.example.first", "com.example.second",
        ])
    }

    /// The gauge's levels, as the row has always drawn them.
    @Test(arguments: [
        (0.0, Coalition.EnergyLevel.medium),
        (299.9, .medium),
        (300, .high),
        (899.9, .high),
        (900, .veryHigh),
        (1999.9, .veryHigh),
        (2000, .batteryDraining),
        (25_000, .batteryDraining),
    ])
    func theEnergyLevelOfAnImpact(impact: Double, level: Coalition.EnergyLevel) {
        #expect(coalition(energyImpact: impact).energyLevel == level)
    }
}
