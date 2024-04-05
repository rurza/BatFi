//
//  DockIconClient.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import Foundation
import Dependencies
import DependenciesMacros

@DependencyClient
public struct DockIconClient {
    public var show: @Sendable (Bool) async -> Void
}

extension DockIconClient: TestDependencyKey {
    public static var testValue: DockIconClient = .init()
}

public extension DependencyValues {
    var dockIcon: DockIconClient {
        get { self[DockIconClient.self] }
        set { self[DockIconClient.self] = newValue }
    }
}
