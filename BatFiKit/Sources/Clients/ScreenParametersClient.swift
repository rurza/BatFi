//
//  ScreenParametersClient.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import Dependencies
import Foundation

public struct ScreenParametersClient: TestDependencyKey {
    public var screenDidChangeParameters: () -> AsyncStream<Void>

    public init(screenDidChangeParameters: @escaping () -> AsyncStream<Void>) {
        self.screenDidChangeParameters = screenDidChangeParameters
    }

    public static var testValue: ScreenParametersClient = unimplemented()
}

extension DependencyValues {
    public var screenParametersClient: ScreenParametersClient {
        get { self[ScreenParametersClient.self] }
        set { self[ScreenParametersClient.self] = newValue }
    }
}
