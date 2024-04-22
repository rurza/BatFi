//
//  AnalyticsClient.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Dependencies
import DependenciesMacros

public enum BreadcrumbCategory: String {
    case chargingManager = "Charging Manager"
    case lifecycle = "app.lifecycle"
}

@DependencyClient
public struct AnalyticsClient {
    public var startSDK: @Sendable () async -> Void = { }
    public var captureMessage: @Sendable (_ message: String) async -> Void = { _ in }
    public var captureError: @Sendable (_ error: Error) async -> Void = { _ in }
    public var addBreadcrumb: @Sendable (_ category: BreadcrumbCategory, _ message: String) async -> Void = { _, _ in }
    public var closeSDK: @Sendable () async -> Void = { }
}

extension AnalyticsClient: TestDependencyKey {
    public static var testValue: AnalyticsClient = .init()
}

extension DependencyValues {
    public var analyticsClient: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}
