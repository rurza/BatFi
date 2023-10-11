import AppShared
import Dependencies

public struct SystemStatsClient: TestDependencyKey {
    public var topCoalitionInfoChanges: () -> AsyncStream<TopCoalitionInfo>
    public var batteryChargeGraphInfoChanges: () -> AsyncStream<BatteryChargeGraphInfo>
    
    public init(
        topCoalitionInfoChanges: @escaping () -> AsyncStream<TopCoalitionInfo>,
        batteryChargeGraphInfoChanges: @escaping () -> AsyncStream<BatteryChargeGraphInfo>
    ) {
        self.topCoalitionInfoChanges = topCoalitionInfoChanges
        self.batteryChargeGraphInfoChanges = batteryChargeGraphInfoChanges
    }
    
    public static var testValue: SystemStatsClient = unimplemented()
}

extension DependencyValues {
    public var systemStatsClient: SystemStatsClient {
        get { self[SystemStatsClient.self] }
        set { self[SystemStatsClient.self] = newValue }
    }
}
