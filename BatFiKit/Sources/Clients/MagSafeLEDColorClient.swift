//
//  MagSafeLEDColorClient.swift
//
//
//  Created by Adam on 16/07/2023.
//

import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct MagSafeLEDColorClient: Sendable {
    public var changeMagSafeLEDColor: @Sendable (MagSafeLEDOption) async throws -> MagSafeLEDOption
    public var currentMagSafeLEDOption: @Sendable () async throws -> MagSafeLEDOption
}

extension MagSafeLEDColorClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: MagSafeLEDColorClient = .init()
}

public extension DependencyValues {
    var magSafeLEDColor: MagSafeLEDColorClient {
        get { self[MagSafeLEDColorClient.self] }
        set { self[MagSafeLEDColorClient.self] = newValue }
    }
}
