//
//  MenuDelegate.swift
//
//
//  Created by Adam on 06/11/2023.
//

import AppKit
import AppShared
import Dependencies
import Shared

public struct MenuDelegate: TestDependencyKey, Sendable {
    public var observeMenu: @Sendable () async -> AsyncStream<Bool>

    public init(observeMenu: @escaping @Sendable () async -> AsyncStream<Bool>) {
        self.observeMenu = observeMenu
    }

    nonisolated(unsafe) public static var testValue: MenuDelegate = unimplemented()
}

public extension DependencyValues {
    var menuDelegate: MenuDelegate {
        get { self[MenuDelegate.self] }
        set { self[MenuDelegate.self] = newValue }
    }
}

@MainActor
public final class MenuObserver: NSObject, NSMenuDelegate {
    @Published
    public private(set) var menuIsOpened: Bool = false

    public static let shared = MenuObserver()

    public func menuWillOpen(_: NSMenu) {
        menuIsOpened = true
        raiseTheAppsWindows()
    }

    public func menuDidClose(_: NSMenu) {
        menuIsOpened = false
    }

    /// Brings every open BatFi window to the front, with the most recently used one key.
    ///
    /// The status item is the only way into this app — there is no Dock icon to click, so
    /// a window that has gone behind a larger one is otherwise reachable only through
    /// Mission Control. Opening the menu is the user asking for BatFi, so it raises what
    /// BatFi has open.
    ///
    /// It also repairs the deactivation the click itself caused: macOS fronts the
    /// previously active app before any of this code runs, which is what buried the window
    /// in the first place. See `StatusMenuActivation`. Re-activating here is measured not
    /// to disturb the menu — it stays open.
    ///
    /// Does nothing when no window is open, which is the common case. Activating then
    /// would take focus from whatever the user is working in and show them nothing.
    private func raiseTheAppsWindows() {
        let windows = StatusMenuActivation.windowsToRaise(
            orderedWindows: NSApp.orderedWindows,
            isOnScreen: \.isVisible,
            canBecomeKey: \.canBecomeKey
        )
        guard let mostRecentlyUsed = windows.last else { return }
        activateApp()
        // Back to front, so the window the user last had in front is left on top.
        for window in windows.dropLast() {
            window.orderFront(nil)
        }
        mostRecentlyUsed.makeKeyAndOrderFront(nil)
    }
}
