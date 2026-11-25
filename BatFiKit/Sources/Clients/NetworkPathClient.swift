//
//  NetworkPathClient.swift
//  BatFi
//
//  Network path changes, as a cheap hint that the Mac may have moved: joining a different
//  Wi-Fi network is the most common sign of arriving somewhere.
//

import Dependencies
import Foundation

public struct NetworkPathClient: TestDependencyKey, Sendable {
    /// Fires when the network path changes to a usable one. The path in force at subscription
    /// is not reported, and losing connectivity is not either: no location fix can follow it.
    public var pathChanges: @Sendable () -> AsyncStream<Void>

    public init(pathChanges: @escaping @Sendable () -> AsyncStream<Void>) {
        self.pathChanges = pathChanges
    }

    nonisolated(unsafe) public static var testValue: NetworkPathClient = unimplemented()
}

public extension DependencyValues {
    var networkPathClient: NetworkPathClient {
        get { self[NetworkPathClient.self] }
        set { self[NetworkPathClient.self] = newValue }
    }
}
