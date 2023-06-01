//
//  LaunchAtLogin.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Dependencies
import Foundation

public struct LaunchAtLogin: TestDependencyKey {
    public var launchAtLogin: (Bool) -> Void

    public init(launchAtLogin: @escaping (Bool) -> Void) {
        self.launchAtLogin = launchAtLogin
    }

    public static var testValue: LaunchAtLogin = unimplemented()
}

extension DependencyValues {
    public var launchAtLogin: LaunchAtLogin {
        get { self[LaunchAtLogin.self] }
        set { self[LaunchAtLogin.self] = newValue }
    }
}
