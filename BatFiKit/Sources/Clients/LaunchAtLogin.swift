//
//  LaunchAtLogin.swift
//
//
//  Created by Adam on 01/06/2023.
//

import Dependencies
import Foundation

public struct LaunchAtLogin: TestDependencyKey, Sendable {
    public var launchAtLogin: @Sendable (Bool) -> Void

    public init(launchAtLogin: @escaping @Sendable (Bool) -> Void) {
        self.launchAtLogin = launchAtLogin
    }

    nonisolated(unsafe) public static var testValue: LaunchAtLogin = unimplemented()
}

public extension DependencyValues {
    var launchAtLogin: LaunchAtLogin {
        get { self[LaunchAtLogin.self] }
        set { self[LaunchAtLogin.self] = newValue }
    }
}
