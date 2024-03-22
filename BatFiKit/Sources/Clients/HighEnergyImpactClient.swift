import AppShared
import Dependencies
import Foundation

public struct HighEnergyImpactClient: TestDependencyKey {
    public var topCoalitionInfoChanges: (_ threshold: Int, _ duration: TimeInterval, _ capacity: Int) -> AsyncStream<TopCoalitionInfo>

    public init(topCoalitionInfoChanges: @escaping (Int, TimeInterval, Int) -> AsyncStream<TopCoalitionInfo>) {
        self.topCoalitionInfoChanges = topCoalitionInfoChanges
    }

    public static var testValue: HighEnergyImpactClient = unimplemented()
}

public extension DependencyValues {
    var highEnergyImpactClient: HighEnergyImpactClient {
        get { self[HighEnergyImpactClient.self] }
        set { self[HighEnergyImpactClient.self] = newValue }
    }
}
