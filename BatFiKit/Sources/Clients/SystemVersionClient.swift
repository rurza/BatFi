//
//  SystemVersionClient.swift
//  BatFiKit
//
//  Created by Adam Różyński on 12/08/2024.
//

import Dependencies

public struct SystemVersionClient: TestDependencyKey {
    public var currentSystemIsSequoiaOrNewer: () -> Bool

    public init(currentSystemIsSequoiaOrNewer: @escaping () -> Bool) {
        self.currentSystemIsSequoiaOrNewer = currentSystemIsSequoiaOrNewer
    }

    public static var testValue: SystemVersionClient = unimplemented()
}

public extension DependencyValues {
    var systemVersionClient: SystemVersionClient {
        get { self[SystemVersionClient.self] }
        set { self[SystemVersionClient.self] = newValue }
    }
}
