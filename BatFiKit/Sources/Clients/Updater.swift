//
//  Updater.swift
//
//
//  Created by Adam on 17/05/2023.
//

import Dependencies

public struct Updater: TestDependencyKey, Sendable {
    /// Brings the updater to life, which is what arms its scheduled update checks.
    /// Separate from merely resolving the dependency because the updater has to be
    /// built on the main actor, and the app starts up off it.
    public var startUpdater: @Sendable () -> Void
    public var checkForUpdates: @Sendable () -> Void
    /// The two getters run on the main actor because they answer synchronously and
    /// Sparkle only allows its settings to be read there.
    public var automaticallyChecksForUpdates: @MainActor @Sendable () -> Bool
    public var automaticallyDownloadsUpdates: @MainActor @Sendable () -> Bool
    public var setAutomaticallyChecksForUpdates: @Sendable (Bool) -> Void
    public var setAutomaticallyDownloadsUpdates: @Sendable (Bool) -> Void

    public init(
        startUpdater: @escaping @Sendable () -> Void,
        checkForUpdates: @escaping @Sendable () -> Void,
        automaticallyChecksForUpdates: @escaping @MainActor @Sendable () -> Bool,
        automaticallyDownloadsUpdates: @escaping @MainActor @Sendable () -> Bool,
        setAutomaticallyChecksForUpdates: @escaping @Sendable (Bool) -> Void,
        setAutomaticallyDownloadsUpdates: @escaping @Sendable (Bool) -> Void
    ) {
        self.startUpdater = startUpdater
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
