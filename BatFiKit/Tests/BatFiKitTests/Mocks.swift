import Foundation
import Defaults
import Clients
import AppShared
import Dependencies

// MARK: - Mock Defaults
class MockDefaults: DefaultsProtocol {
    private var storage: [String: Any] = [:]
    private var continuations: [String: [AsyncStream<Any>.Continuation]] = [:]
    
    func observe<Value>(_ key: Defaults.Key<Value>) -> AsyncStream<Value> where Value : Defaults.Serializable, Value : CustomStringConvertible, Value : Equatable {
        return AsyncStream { continuation in
            // Send current value immediately
            let value = value(key)
            continuation.yield(value)
            
            // Store continuation for future updates
            // In a real implementation we'd need type erasure or careful storage, 
            // for now we'll simplify and just not support live updates in this basic mock unless needed.
            // A more robust mock would store `(Any) -> Void` handlers.
        }
    }
    
    func setValue<Value>(_ key: Defaults.Key<Value>, value: Value) where Value : Defaults.Serializable {
        storage[key.name] = value
    }
    
    func value<Value>(_ key: Defaults.Key<Value>) -> Value where Value : Defaults.Serializable {
        return storage[key.name] as? Value ?? key.defaultValue
    }
    
    func resetSettings() {
        storage.removeAll()
    }
}
