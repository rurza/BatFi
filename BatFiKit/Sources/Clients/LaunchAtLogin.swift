//
//  LaunchAtLogin.swift
//
//
//  Created by Adam on 01/06/2023.
//

import Dependencies
import Foundation

public struct LaunchAtLogin: TestDependencyKey {
    public var launchAtLogin: @Sendable (Bool) async -> Void

    public init(launchAtLogin: @Sendable @escaping (Bool) async -> Void) {
        self.launchAtLogin = launchAtLogin
    }

    public static var testValue: LaunchAtLogin = unimplemented()
}

public extension DependencyValues {
    var launchAtLogin: LaunchAtLogin {
        get { self[LaunchAtLogin.self] }
        set { self[LaunchAtLogin.self] = newValue }
    }
}
