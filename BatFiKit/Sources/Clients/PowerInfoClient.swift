import Dependencies
import Shared

public struct PowerInfoClient: TestDependencyKey {
    public var powerInfoChanges: () -> AsyncStream<PowerInfo>

    public init(powerInfoChanges: @escaping () -> AsyncStream<PowerInfo>) {
        self.powerInfoChanges = powerInfoChanges
    }

    public static var testValue: PowerInfoClient = unimplemented()
}

public extension DependencyValues {
    var powerInfoClient: PowerInfoClient {
        get { self[PowerInfoClient.self] }
        set { self[PowerInfoClient.self] = newValue }
    }
}
