import Dependencies
import Shared

public struct PowerDistributionClient: TestDependencyKey, Sendable {
    public var powerInfoChanges: @Sendable () -> AsyncStream<PowerDistributionInfo>

    public init(powerInfoChanges: @escaping @Sendable () -> AsyncStream<PowerDistributionInfo>) {
        self.powerInfoChanges = powerInfoChanges
    }

    nonisolated(unsafe) public static var testValue: PowerDistributionClient = unimplemented()
}

public extension DependencyValues {
    var powerDistributionClient: PowerDistributionClient {
        get { self[PowerDistributionClient.self] }
        set { self[PowerDistributionClient.self] = newValue }
    }
}
