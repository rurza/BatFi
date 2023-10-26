import AppShared
import Dependencies

public struct HighEnergyImpactClient: TestDependencyKey {
    public var topCoalitionInfoChanges: () -> AsyncStream<TopCoalitionInfo>
    
    public init(topCoalitionInfoChanges: @escaping () -> AsyncStream<TopCoalitionInfo>) {
        self.topCoalitionInfoChanges = topCoalitionInfoChanges
    }
    
    public static var testValue: HighEnergyImpactClient = unimplemented()
}

extension DependencyValues {
    public var highEnergyImpactClient: HighEnergyImpactClient {
        get { self[HighEnergyImpactClient.self] }
        set { self[HighEnergyImpactClient.self] = newValue }
    }
}
