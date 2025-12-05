//
//  SystemVersionClient.swift
//  BatFiKit
//
//  Created by Adam Różyński on 12/08/2024.
//

import Dependencies

public struct SystemVersionClient: TestDependencyKey {
    public var currentSystemIsSequoiaOrNewer: () -> Bool
    public var currentSystemIsTahoeOrNewer: () -> Bool
    public var majorVersion: () -> Int

    public init(
        currentSystemIsSequoiaOrNewer: @escaping () -> Bool,
        currentSystemIsTahoeOrNewer: @escaping () -> Bool = { false },
        majorVersion: @escaping () -> Int = { 0 }
    ) {
        self.currentSystemIsSequoiaOrNewer = currentSystemIsSequoiaOrNewer
        self.currentSystemIsTahoeOrNewer = currentSystemIsTahoeOrNewer
        self.majorVersion = majorVersion
    }

    public static var testValue: SystemVersionClient = unimplemented()
}

public extension DependencyValues {
    var systemVersionClient: SystemVersionClient {
        get { self[SystemVersionClient.self] }
        set { self[SystemVersionClient.self] = newValue }
    }
}
