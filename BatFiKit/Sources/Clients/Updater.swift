//
//  Updater.swift
//
//
//  Created by Adam on 17/05/2023.
//

import Dependencies

public struct Updater: TestDependencyKey, Sendable {
    public var checkForUpdates: @Sendable () -> Void
    public var automaticallyChecksForUpdates: @Sendable () -> Bool
    public var automaticallyDownloadsUpdates: @Sendable () -> Bool
    public var setAutomaticallyChecksForUpdates: @Sendable (Bool) -> Void
    public var setAutomaticallyDownloadsUpdates: @Sendable (Bool) -> Void

    public init(
        checkForUpdates: @escaping @Sendable () -> Void,
        automaticallyChecksForUpdates: @escaping @Sendable () -> Bool,
        automaticallyDownloadsUpdates: @escaping @Sendable () -> Bool,
        setAutomaticallyChecksForUpdates: @escaping @Sendable (Bool) -> Void,
        setAutomaticallyDownloadsUpdates: @escaping @Sendable (Bool) -> Void
    ) {
        self.checkForUpdates = checkForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        self.setAutomaticallyChecksForUpdates = setAutomaticallyChecksForUpdates
        self.setAutomaticallyDownloadsUpdates = setAutomaticallyDownloadsUpdates
    }

    nonisolated(unsafe) public static var testValue: Updater = unimplemented()
}

public extension DependencyValues {
    var updater: Updater {
        get { self[Updater.self] }
        set { self[Updater.self] = newValue }
    }
}
