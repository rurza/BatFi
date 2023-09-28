//
//  File.swift
//  
//
//  Created by Adam on 13/06/2023.
//

import Defaults
import DefaultsKeys
import Dependencies
import Foundation

public protocol DefaultsProtocol {
    func observe<Value: Defaults.Serializable & CustomStringConvertible & Equatable>(_ key: Defaults.Key<Value>) -> AsyncStream<Value>
    func setValue<Value: Defaults.Serializable>(_ key: Defaults.Key<Value>, value: Value)
    func value<Value: Defaults.Serializable>(_ key: Defaults.Key<Value>) -> Value
    func resetSettings()
}

public enum DefaultsKey: TestDependencyKey {
  public static let testValue: any DefaultsProtocol = unimplemented()
}

extension DependencyValues {
    public var defaults: any DefaultsProtocol {
        get { self[DefaultsKey.self] }
        set { self[DefaultsKey.self] = newValue }
    }
}
