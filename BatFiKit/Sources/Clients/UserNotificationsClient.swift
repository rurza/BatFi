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
public struct UserNotificationsClient {
    public var requestAuthorization: @Sendable () async -> Bool? = { nil }
    public var showUserNotification: @Sendable (_ title: String, _ body: String, _ identifier: String, _ threadIdentifier: String?, _ delay: TimeInterval?) async throws -> Void
}

extension UserNotificationsClient: TestDependencyKey {
    public static var testValue: UserNotificationsClient = UserNotificationsClient()
}

public extension DependencyValues {
    var userNotificationsClient: UserNotificationsClient {
        get { self[UserNotificationsClient.self] }
        set { self[UserNotificationsClient.self] = newValue }
    }
}

