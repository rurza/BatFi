//
//  Updater.swift
//
//
//  Created by Adam on 17/05/2023.
//

import Dependencies

public struct Updater: TestDependencyKey {
    public var checkForUpdates: @Sendable () async -> Void
    public var automaticallyChecksForUpdates: @Sendable () async -> Bool
    public var automaticallyDownloadsUpdates: @Sendable () async -> Bool
    public var setAutomaticallyChecksForUpdates: @Sendable (Bool) async -> Void
    public var setAutomaticallyDownloadsUpdates: @Sendable (Bool) async -> Void
    public var setAllowBetaVersion: @Sendable (Bool) async -> Void

    public init(
        checkForUpdates: @Sendable @escaping () async -> Void,
        automaticallyChecksForUpdates: @Sendable @escaping () async -> Bool,
        automaticallyDownloadsUpdates: @Sendable @escaping () async -> Bool,
        setAutomaticallyChecksForUpdates: @Sendable @escaping (Bool) async -> Void,
        setAutomaticallyDownloadsUpdates: @Sendable @escaping (Bool) async -> Void,
        setAllowBetaVersion: @Sendable @escaping (Bool) async -> Void
    ) {
        self.checkForUpdates = checkForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        self.setAutomaticallyChecksForUpdates = setAutomaticallyChecksForUpdates
        self.setAutomaticallyDownloadsUpdates = setAutomaticallyDownloadsUpdates
        self.setAllowBetaVersion = setAllowBetaVersion
    }

    public static var testValue: Updater = unimplemented()
}

public extension DependencyValues {
    var updater: Updater {
        get { self[Updater.self] }
        set { self[Updater.self] = newValue }
    }
}
