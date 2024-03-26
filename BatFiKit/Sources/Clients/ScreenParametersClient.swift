//
//  ScreenParametersClient.swift
//
//
//  Created by Adam on 04/05/2023.
//

import Dependencies
import Foundation

public struct ScreenParametersClient: TestDependencyKey {
    public var screenDidChangeParameters: @Sendable () async -> AsyncStream<Void>

    public init(screenDidChangeParameters: @Sendable @escaping () async -> AsyncStream<Void>) {
        self.screenDidChangeParameters = screenDidChangeParameters
    }

    public static var testValue: ScreenParametersClient = unimplemented()
}

public extension DependencyValues {
    var screenParametersClient: ScreenParametersClient {
        get { self[ScreenParametersClient.self] }
        set { self[ScreenParametersClient.self] = newValue }
    }
}
