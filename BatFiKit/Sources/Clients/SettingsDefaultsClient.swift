//
//  SettingsDefaultsClient.swift
//  
//
//  Created by Adam on 18/05/2023.
//

import Dependencies
import Foundation

public struct SettingsDefaultsClient: TestDependencyKey {
    public var showBatteryPercentage: (Bool?) -> Bool
    public var observeShowBatteryPercentage: () -> AsyncStream<Bool>
    public var showMonochromeIcon: (Bool?) -> Bool
    public var observeShowMonochromeIcon: () -> AsyncStream<Bool>
    public var launchAtLogin: (Bool?) -> Bool
    public var onboardingIsDone: (Bool?) -> Bool

    public init(
        showBatteryPercentage: @escaping (Bool?) -> Bool,
        observeShowBatteryPercentage: @escaping () -> AsyncStream<Bool>,
        showMonochromeIcon: @escaping (Bool?) -> Bool,
        observeShowMonochromeIcon: @escaping () -> AsyncStream<Bool>,
        launchAtLogin: @escaping (Bool?) -> Bool,
        onboardingIsDone: @escaping (Bool?) -> Bool
    ) {
        self.showBatteryPercentage = showBatteryPercentage
        self.observeShowBatteryPercentage = observeShowBatteryPercentage
        self.showMonochromeIcon = showMonochromeIcon
        self.observeShowMonochromeIcon = observeShowMonochromeIcon
        self.launchAtLogin = launchAtLogin
        self.onboardingIsDone = onboardingIsDone
    }

    public static var testValue: SettingsDefaultsClient = unimplemented()
}

extension DependencyValues {
    public var settingsDefaultsClient: SettingsDefaultsClient {
        get { self[SettingsDefaultsClient.self] }
        set { self[SettingsDefaultsClient.self] = newValue }
    }
}
