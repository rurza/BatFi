//
//  Constants.swift
//
//
//  Created by Adam on 14/04/2023.
//

import Foundation

public enum Constant {
    public static let appBundleIdentifier = "software.micropixels.BatFi"
    public static let helperBundleIdentifier = "software.micropixels.BatFi.Helper"
    public static let helperPlistName = helperBundleIdentifier + ".plist"
    /// Path of the helper executable inside the app bundle. Mirrors `BundleProgram` in
    /// `software.micropixels.BatFi.Helper.plist`, which is what launchd actually starts;
    /// the two have to agree, or the app would compare the running helper against a
    /// location nothing is ever installed to.
    public static let helperBundleProgramPath = "Contents/MacOS/BatFiHelper"
    public static let batteryTemperatureWarning: Double = 40
}
