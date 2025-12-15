import XCTest
import Dependencies
import AppCore
import AppShared
import Clients
import Shared
import DefaultsKeys
import Defaults
import AsyncAlgorithms

final class ChargingManagerTests: XCTestCase {
    
    func test_initialMode_updates_to_charging() async throws {
        // Setup
        let chargingModeDidSet = AsyncStream<AppChargingMode>.makeStream()
        
        let powerStateStream = AsyncStream<PowerState>.makeStream()
        
        // Mock Data
        let initialPowerState = PowerState(
            batteryLevel: 50,
            isCharging: true,
            powerSource: "AC",
            timeLeft: 0,
            timeToCharge: 60,
            batteryCycleCount: 10,
            batteryHealth: 100,
            batteryTemperature: 25.0,
            chargerConnected: true,
            optimizedBatteryChargingEngaged: false
        )
        
        let chargingStatus = SMCChargingStatus(
            forceDischarging: false,
            inhitbitCharging: false,
            lidClosed: false,
            systemChargeLimit: false
        )
        
        // Mocks
        let mockDefaults = MockDefaults()
        mockDefaults.setValue(.chargeLimit, value: 80)
        mockDefaults.setValue(.manageCharging, value: true)
        
        try await withDependencies {
            $0.defaults = mockDefaults
            $0.chargingClient.chargingStatus = { chargingStatus }
            $0.powerSourceClient.powerSourceChanges = { powerStateStream.stream }
            $0.powerSourceClient.currentPowerSourceState = { initialPowerState }
            
            // AppChargingStateClient Mocks
            $0.appChargingState.currentUserTempOverrideMode = { nil }
            $0.appChargingState.currentAppChargingMode = { .init(mode: .initial, userTempOverride: nil, chargerConnected: true) }
            $0.appChargingState.lidOpened = { true }
            $0.appChargingState.setAppChargingMode = { mode in
                chargingModeDidSet.continuation.yield(mode)
            }
            $0.appChargingState.setChargerConnected = { _ in }
            $0.appChargingState.updateLidOpenedStatus = { _ in }
            
            // Sleep Clients (Passive)
            $0.sleepClient.observeMacSleepStatus = { AsyncStream { _ in } }
            $0.sleepClient.macWillSleep = { AsyncStream { _ in } }
            $0.screenParametersClient.screenDidChangeParameters = { AsyncStream { _ in } }
            $0.sleepAssertionClient.preventsAutomaticSleep = { false }
            $0.sleepAssertionClient.preventAutomaticSleepIfNeeded = { _ in }
            
            // Analytics
            $0.analyticsClient.addBreadcrumb = { _, _ in }
            
        } operation: {
            let manager = ChargingManager()
            manager.setUpObserving()
            
            // Trigger the flow
            powerStateStream.continuation.yield(initialPowerState)
            
            // Wait for the mode update
            var iterator = chargingModeDidSet.stream.makeAsyncIterator()
            
            // It might take a moment or a few loop iterations
            // We expect it to transition to .charging (since we are at 50% and limit is 80%)
            // The logic: 50 < 80 -> turnOnCharging -> mode = .charging
            
            let resultMode = await iterator.next()
            
            XCTAssertNotNil(resultMode)
            XCTAssertEqual(resultMode?.mode, .charging)
            XCTAssertEqual(resultMode?.chargerConnected, true)
        }
    }
}

// MARK: - Mock Defaults
class MockDefaults: DefaultsProtocol {
    private var storage: [String: Any] = [:]
    
    func observe<Value>(_ key: Defaults.Key<Value>) -> AsyncStream<Value> where Value : Defaults.Serializable, Value : CustomStringConvertible, Value : Equatable {
        let value = storage[key.name] as? Value ?? key.defaultValue
        return AsyncStream { continuation in
            continuation.yield(value)
            // In a real mock, we might want to observe changes, but for now just yielding current is enough for initial setup
            // continuation.finish() // Don't finish, or the loop might exit
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
