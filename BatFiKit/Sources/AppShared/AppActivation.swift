//
//  AppActivation.swift
//
//
//  Created by Adam Różyński on 05/08/2026.
//

import AppKit

/// Brings BatFi to the front. The one place in the app that activates it.
///
/// This one is deprecated but it behavious is different, because it really is ignoring other app
/// and our app, can be actually brint up front and have the key window
public func activateApp() {
    NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
}
