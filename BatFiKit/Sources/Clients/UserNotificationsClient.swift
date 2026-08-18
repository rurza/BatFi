//
//  UserNotificationsClient.swift
//
//
//  Created by Adam Różyński on 27/03/2024.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct UserNotificationsClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Bool? = { nil }
    /// - Parameter identifier: a prefix, not the notification's identifier. The live client
    ///   makes each notification's identifier unique, because reusing one replaces the
    ///   delivered notification instead of posting a new one — and a replacement updates
    ///   Notification Center silently rather than presenting a banner. Group related
    ///   notifications with `threadIdentifier` instead.
    public var showUserNotification: @Sendable (_ title: String, _ body: String, _ identifier: String, _ threadIdentifier: String?, _ delay: TimeInterval?) async throws -> Void
}

extension UserNotificationsClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: UserNotificationsClient = UserNotificationsClient()
}

public extension DependencyValues {
    var userNotificationsClient: UserNotificationsClient {
        get { self[UserNotificationsClient.self] }
        set { self[UserNotificationsClient.self] = newValue }
    }
}

