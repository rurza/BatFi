import Dependencies
import Shared

public struct PowerDistributionClient: TestDependencyKey {
    public var powerInfoChanges: () -> AsyncStream<PowerDistributionInfo>

    public init(powerInfoChanges: @escaping () -> AsyncStream<PowerDistributionInfo>) {
        self.powerInfoChanges = powerInfoChanges
    }

    public static var testValue: PowerDistributionClient = unimplemented()
}

public extension DependencyValues {
    var powerDistributionClient: PowerDistributionClient {
        get { self[PowerDistributionClient.self] }
        set { self[PowerDistributionClient.self] = newValue }
    }
}
