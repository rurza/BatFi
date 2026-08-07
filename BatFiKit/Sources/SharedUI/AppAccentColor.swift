//
//  AppAccentColor.swift
//
//
//  Created by Adam Różyński on 06/08/2026.
//

import AppKit
import SwiftUI

public extension Color {
    /// BatFi's brand green, the same value the app target ships as its `AccentColor`.
    ///
    /// Kept here rather than read from the app's asset catalog because `Color("appGreen")`
    /// resolves against `Bundle.main`: it happens to work inside the running app and returns
    /// nothing anywhere else, so every SwiftUI preview in a package module drew the fallback.
    /// This colour set lives in `SharedUI`'s own bundle, so every module — and every preview —
    /// gets the brand colour.
    ///
    /// Prefer this over `.accentColor` wherever the green is the point rather than "whatever
    /// the user picked in System Settings".
    static let appAccent = Color(.appAccent)
}

public extension NSColor {
    /// AppKit-side counterpart of ``SwiftUI/Color/appAccent``.
    static let appAccent = NSColor(resource: .appAccent)
}
