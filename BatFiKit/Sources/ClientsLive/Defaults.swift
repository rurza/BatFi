//
//  File.swift
//  
//
//  Created by Adam on 13/06/2023.
//

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
    private let logger = Logger(category: "👀🔧")
    
    public func observe<Value>(_ key: Defaults.Key<Value>) -> AsyncStream<Value> where Value : Defaults.Serializable & CustomStringConvertible & Equatable {
        Defaults.updates(key)
            .map {
                logger.debug("\(key.name, privacy: .public) did change: \($0.description, privacy: .public)")
                return $0
            }
            .removeDuplicates()
            .eraseToStream()
    }
    
    public func value<Value>(_ key: Defaults.Key<Value>) -> Value where Value : Defaults.Serializable {
        Defaults[key]
    }
    
    public func setValue<Value>(_ key: Defaults.Key<Value>, value: Value) where Value : Defaults.Serializable {
        Defaults[key] = value
    }
    
    public func resetSettings() {
        UserDefaults.standard.removeAll()
    }
}
