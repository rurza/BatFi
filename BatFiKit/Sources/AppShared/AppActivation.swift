//
//  AppActivation.swift
//
//
//  Created by Adam Różyński on 05/08/2026.
//

import AppKit

/// Brings BatFi to the front. The one place in the app that activates it.
///
/// Every window BatFi opens goes through here first: it normally runs as an accessory app,
/// so a freshly ordered-in window would otherwise land behind whatever the user was in.
///
/// This used to pass `.activateIgnoringOtherApps` at each call site. That option has been a
/// no-op since macOS 14 — below our deployment target — so activating with no options
/// behaves identically on every system BatFi runs on, minus seven deprecation warnings.
public func activateApp() {
    NSRunningApplication.current.activate()
}
