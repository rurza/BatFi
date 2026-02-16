import AppShared
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct EnergyStatsClient: Sendable {
    public var topCoalitionInfoChanges: @Sendable (_ threshold: Int, _ duration: TimeInterval, _ capacity: Int) -> AsyncStream<TopCoalitionInfo> = { _, _, _ in AsyncStream { _ in } }
    public var batteryChargeGraphInfoChanges: @Sendable () -> AsyncStream<BatteryChargeGraphInfo> = { AsyncStream { _ in } }
}

extension EnergyStatsClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: EnergyStatsClient = .init()
}

public extension DependencyValues {
    var energyStatsClient: EnergyStatsClient {
        get { self[EnergyStatsClient.self] }
        set { self[EnergyStatsClient.self] = newValue }
    }
}
