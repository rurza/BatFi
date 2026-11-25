//
//  Defaults.swift
//
//
//  Created by Adam on 13/06/2023.
//

import AppShared
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import Foundation
import os
import Shared

extension DefaultsKey: DependencyKey {
    public static let liveValue: DefaultsProtocol = DefaultsClient()
}

public struct DefaultsClient: DefaultsProtocol {
    private let logger = Logger(category: "DefaultsClient")

    public func observe<Value>(_ key: Defaults.Key<Value>) -> AsyncStream<Value> where Value: DefaultsValue {
        Defaults.updates(key)
            .map {
                logger.debug("\(key.name, privacy: .public) did change: \($0.description, privacy: .public)")
                return $0
            }
            .removeDuplicates()
            .eraseToStream()
    }

    public func observe<Value>(_ key: Defaults.Key<Value?>) -> AsyncStream<Value?> where Value: DefaultsValue {
        Defaults.updates(key)
            .map {
                logger.debug("\(key.name, privacy: .public) did change: \($0?.description ?? "nil", privacy: .public)")
                return $0
            }
            .removeDuplicates()
            .eraseToStream()
    }

    public func value<Value>(_ key: Defaults.Key<Value>) -> Value where Value: Defaults.Serializable {
        Defaults[key]
    }

    public func setValue<Value>(_ key: Defaults.Key<Value>, value: Value) where Value: Defaults.Serializable {
        Defaults[key] = value
    }

    /// Empties `UserDefaults.standard`, except for the records in
    /// `stateKeysPreservedAcrossReset`, which come back holding what they held — or stay
    /// absent where they were never written.
    public func resetSettings() {
        let defaults = UserDefaults.standard
        let preserved = PreservedDefaults(
            keys: Defaults.Keys.stateKeysPreservedAcrossReset.map(\.name),
            // `standard` stores into the app's own domain, named for its bundle identifier,
            // which the app always has. Without one nothing would be kept.
            domainName: Bundle.main.bundleIdentifier ?? "",
            in: defaults
        )
        logger.notice("Resetting settings; state records are kept")
        defaults.removeAll()
        preserved.restore(into: defaults)
    }
}
