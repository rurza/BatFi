import XCTest
import Dependencies
import Clients
import AppShared
import Defaults
import DefaultsKeys
@testable import HighEnergyUsage

final class HighEnergyUsageViewModelTests: XCTestCase {
    
    @MainActor
    func test_topCoalitionInfo_updates_from_client() async throws {
        // Setup
        let coalitionStream = AsyncStream<TopCoalitionInfo>.makeStream()
        
        let mockDefaults = MockDefaults()
        mockDefaults.setValue(.highEnergyImpactProcessesCapacity, value: 5)
        mockDefaults.setValue(.highEnergyImpactProcessesThreshold, value: 100)
        mockDefaults.setValue(.highEnergyImpactProcessesDuration, value: 60)
        
        try await withDependencies {
            $0.defaults = mockDefaults
            $0.energyStatsClient.topCoalitionInfoChanges = { _, _, _ in coalitionStream.stream }
        } operation: {
            let viewModel = HighEnergyUsageViewModel()
            
            // Initial state
            XCTAssertNil(viewModel.topCoalitionInfo)
            
            // Start observing
            viewModel.startObserving()
            
            // Mock Data
            let mockCoalition = Coalition(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                icon: nil,
                energyImpact: 50.0
            )
            let mockInfo = TopCoalitionInfo(topCoalitions: [mockCoalition])
            
            // Emit data
            coalitionStream.continuation.yield(mockInfo)
            
            // Wait for update (allow runloop to cycle)
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Verify
            XCTAssertNotNil(viewModel.topCoalitionInfo)
            XCTAssertEqual(viewModel.topCoalitionInfo?.topCoalitions.first?.bundleIdentifier, "com.apple.Safari")
            
            viewModel.cancelObserving()
        }
    }
}
