//
//  StatusMenuActivationTests.swift
//  BatFi
//
//  Clicking the status item deactivates an accessory app: macOS brings the previously
//  active app forward before any of BatFi's code runs. Measured on macOS 27 in a sixty-line
//  app with none of BatFi's code in it, so it is the OS's behaviour and the only thing
//  available is to put the windows back. With no Dock icon there is no other way to reach
//  a window that has gone behind something.
//

import Foundation
import Testing

@testable import Shared

@Suite struct StatusMenuActivationTests {
    /// Stands in for NSWindow. `order` is only here to make the assertions readable.
    private struct Window: Equatable {
        let name: String
        var isOnScreen = true
        var canBecomeKey = true
    }

    private func raise(_ windows: [Window]) -> [Window] {
        StatusMenuActivation.windowsToRaise(
            orderedWindows: windows,
            isOnScreen: \.isOnScreen,
            canBecomeKey: \.canBecomeKey
        )
    }

    /// The common case by far: the menu is opened from another app with nothing of BatFi's
    /// on screen. An empty list is the instruction to leave the user's focus alone —
    /// activating here would take it and show them nothing.
    @Test func nothingOnScreenRaisesNothing() {
        #expect(raise([]).isEmpty)
        #expect(raise([Window(name: "settings", isOnScreen: false)]).isEmpty)
    }

    /// The status item's own windows are visible at this moment and must never be
    /// mistaken for something to raise.
    @Test func windowsThatCannotBecomeKeyAreNotWindows() {
        let windows = [
            Window(name: "statusBar", canBecomeKey: false),
            Window(name: "settings"),
            Window(name: "statusBar2", canBecomeKey: false),
        ]
        #expect(raise(windows).map(\.name) == ["settings"])
    }

    /// The menu's own window can become key but is not visible yet when this runs.
    @Test func aWindowThatIsNotYetOnScreenIsNotRaised() {
        let windows = [Window(name: "popupMenu", isOnScreen: false), Window(name: "about")]
        #expect(raise(windows).map(\.name) == ["about"])
    }

    /// The order is the whole contract: the caller orders each forward in turn, so the
    /// list has to run back to front for the front-most to end up on top. Getting this
    /// backwards would shuffle the user's windows on every single menu open.
    @Test func theListRunsBackToFrontSoTheFrontMostStaysFront() {
        let windows = [Window(name: "settings"), Window(name: "about"), Window(name: "license")]
        #expect(raise(windows).map(\.name) == ["license", "about", "settings"])
    }

    /// And therefore the last element is the one to make key: the window the user had in
    /// front before the click is the one they get back.
    @Test func theLastOneIsTheMostRecentlyUsed() {
        let windows = [Window(name: "settings"), Window(name: "about")]
        #expect(raise(windows).last?.name == "settings")
    }

    @Test func aSingleWindowIsRaisedAndIsTheKeyOne() {
        #expect(raise([Window(name: "settings")]).map(\.name) == ["settings"])
    }

    /// Filtering happens before the reversal, so an excluded window cannot end up as the
    /// key one by being last in the input.
    @Test func anExcludedWindowNeverBecomesTheKeyOne() {
        let windows = [Window(name: "settings"), Window(name: "statusBar", canBecomeKey: false)]
        #expect(raise(windows).last?.name == "settings")
    }
}
