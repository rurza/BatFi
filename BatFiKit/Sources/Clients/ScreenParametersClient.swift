//
//  ScreenParametersClient.swift
//
//
//  Created by Adam on 04/05/2023.
//

import Dependencies
import Foundation

public struct ScreenParametersClient: TestDependencyKey, Sendable {
    public var screenDidChangeParameters: @Sendable () -> AsyncStream<Void>

    public init(screenDidChangeParameters: @escaping @Sendable () -> AsyncStream<Void>) {
        self.screenDidChangeParameters = screenDidChangeParameters
    }

    nonisolated(unsafe) public static var testValue: ScreenParametersClient = unimplemented()
}

public extension DependencyValues {
    var screenParametersClient: ScreenParametersClient {
        get { self[ScreenParametersClient.self] }
        set { self[ScreenParametersClient.self] = newValue }
    }
}
