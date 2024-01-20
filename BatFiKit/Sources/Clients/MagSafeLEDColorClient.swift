//
//  MagSafeLEDColorClient.swift
//
//
//  Created by Adam on 16/07/2023.
//

import Dependencies
import Foundation
import Shared

public struct MagSafeLEDColorClient: TestDependencyKey {
    public var changeMagSafeLEDColor: (MagSafeLEDOption) async throws -> MagSafeLEDOption

    public static var testValue: MagSafeLEDColorClient = unimplemented()

    public init(changeMagSafeLEDColor: @escaping (MagSafeLEDOption) async throws -> MagSafeLEDOption) {
        self.changeMagSafeLEDColor = changeMagSafeLEDColor
    }
}

public extension DependencyValues {
    var magSafeLEDColor: MagSafeLEDColorClient {
        get { self[MagSafeLEDColorClient.self] }
        set { self[MagSafeLEDColorClient.self] = newValue }
    }
}
