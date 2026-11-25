//
//  SystemVersionClient.swift
//  BatFiKit
//
//  Created by Adam Różyński on 12/08/2024.
//

import Dependencies

public struct SystemVersionClient: TestDependencyKey, Sendable {
    public var currentSystemIsSequoiaOrNewer: @Sendable () -> Bool

    public init(currentSystemIsSequoiaOrNewer: @escaping @Sendable () -> Bool) {
        self.currentSystemIsSequoiaOrNewer = currentSystemIsSequoiaOrNewer
    }

    nonisolated(unsafe) public static var testValue: SystemVersionClient = unimplemented()
}

public extension DependencyValues {
    var systemVersionClient: SystemVersionClient {
        get { self[SystemVersionClient.self] }
        set { self[SystemVersionClient.self] = newValue }
    }
}
