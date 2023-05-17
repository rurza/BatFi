//
//  Updater.swift
//  
//
//  Created by Adam on 17/05/2023.
//

import Dependencies

public struct Updater: TestDependencyKey {
    public var checkForUpdates: () -> Void
    public var automaticallyChecksForUpdates: () -> Bool
    public var automaticallyDownloadsUpdates: () -> Bool
    public var setAutomaticallyChecksForUpdates: (Bool) -> Void
    public var setAutomaticallyDownloadsUpdates: (Bool) -> Void

    public init(
        checkForUpdates: @escaping () -> Void,
        automaticallyChecksForUpdates: @escaping () -> Bool,
        automaticallyDownloadsUpdates: @escaping () -> Bool,
        setAutomaticallyChecksForUpdates: @escaping (Bool) -> Void,
        setAutomaticallyDownloadsUpdates: @escaping (Bool) -> Void
    ) {
        self.checkForUpdates = checkForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        self.setAutomaticallyChecksForUpdates = setAutomaticallyChecksForUpdates
        self.setAutomaticallyDownloadsUpdates = setAutomaticallyDownloadsUpdates
    }

    public static var testValue: Updater = unimplemented()
}

extension DependencyValues {
    public var updater: Updater {
        get { self[Updater.self] }
        set { self[Updater.self] = newValue }
    }
}
