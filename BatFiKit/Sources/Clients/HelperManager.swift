//
//  HelperManager.swift
//  BatFi
//
//  Created by Adam on 22/04/2023.
//

import Dependencies
import ServiceManagement

public struct HelperManager: TestDependencyKey {
    public var installHelper: () async throws -> Void
    public var removeHelper: () async throws -> Void
    public var helperStatus: () async -> SMAppService.Status

    public init(
        installHelper: @escaping () async throws -> Void,
        removeHelper: @escaping () async throws -> Void,
        helperStatus: @escaping () async -> SMAppService.Status
    ) {
        self.installHelper = installHelper
        self.removeHelper = removeHelper
        self.helperStatus = helperStatus
    }

    public static var testValue: HelperManager = unimplemented()
}

extension DependencyValues {
    public var helperManager: HelperManager {
        get { self[HelperManager.self] }
        set { self[HelperManager.self] = newValue }
    }
}
