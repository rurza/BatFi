//
//  StatusMenuActivation.swift
//
//
//  Which windows the status menu should raise, and which one should end up key.
//
//  Clicking a status item deactivates an accessory app. Measured on macOS 27: the click
//  posts `NSWorkspace.didActivateApplication` for the *previous* app and
//  `NSApplicationDidResignActive` for ours before any of our code runs at all — with the
//  menu attached to the status item the first hook is `menuWillOpen`, and with a plain
//  button action the event still only arrives 16ms *after* the deactivation. There is no
//  way to prevent it, so the app puts itself back.
//
//  BatFi has no Dock icon, so the status item is the only way to reach a window that has
//  gone behind something. That makes raising them the menu's job rather than a repair for
//  the deactivation: every open window comes forward on every menu open, and the one the
//  user had in front stays in front.
//

import Foundation

public enum StatusMenuActivation {
    /// The windows to raise when the status menu opens, ordered **back to front**, so
    /// ordering each one forward in turn leaves the front-most where it was. The last
    /// element is the one to make key.
    ///
    /// Returns empty when there is nothing on screen, which is the common case — a menu
    /// opened from another app with no BatFi window anywhere. Activating then would take
    /// focus from the user's app and show them nothing, so the caller must do nothing at
    /// all rather than activate with an empty list.
    ///
    /// - Parameters:
    ///   - orderedWindows: the app's windows, front-most first. `NSApp.orderedWindows`
    ///     keeps this order while the app is inactive, which is exactly when this runs.
    ///   - isOnScreen: `isVisible`. Excludes closed windows, and windows never shown.
    ///   - canBecomeKey: `canBecomeKey`. This is what separates a real window from the
    ///     rest of `NSApp.windows`, which on an accessory app with a status item is mostly
    ///     infrastructure: measured at this exact moment on macOS 27, two
    ///     `NSStatusBarWindow` (visible, never key) and an `NSPopupMenuWindow` for the menu
    ///     about to open (can become key, not yet visible).
    public static func windowsToRaise<Window>(
        orderedWindows: [Window],
        isOnScreen: (Window) -> Bool,
        canBecomeKey: (Window) -> Bool
    ) -> [Window] {
        orderedWindows
            .filter { isOnScreen($0) && canBecomeKey($0) }
            .reversed()
    }
}
