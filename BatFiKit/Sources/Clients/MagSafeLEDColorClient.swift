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
public struct MagSafeLEDColorClient {
    public var changeMagSafeLEDColor: (MagSafeLEDOption) async throws -> MagSafeLEDOption
    public var currentMagSafeLEDOption: () async throws -> MagSafeLEDOption
}

extension MagSafeLEDColorClient: TestDependencyKey {
    public static var testValue: MagSafeLEDColorClient = .init()
}

public extension DependencyValues {
    var magSafeLEDColor: MagSafeLEDColorClient {
        get { self[MagSafeLEDColorClient.self] }
        set { self[MagSafeLEDColorClient.self] = newValue }
    }
}
