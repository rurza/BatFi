import AppShared
import Dependencies

public struct SystemStatsClient: TestDependencyKey {
    public var topCoalitionInfoChanges: () -> AsyncStream<TopCoalitionInfo>
    
    public init(topCoalitionInfoChanges: @escaping () -> AsyncStream<TopCoalitionInfo>) {
        self.topCoalitionInfoChanges = topCoalitionInfoChanges
    }
    
    public static var testValue: SystemStatsClient = unimplemented()
}

extension DependencyValues {
    public var systemStatsClient: SystemStatsClient {
        get { self[SystemStatsClient.self] }
        set { self[SystemStatsClient.self] = newValue }
    }
}
