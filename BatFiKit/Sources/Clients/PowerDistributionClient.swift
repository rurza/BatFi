import Dependencies
import Shared

public struct PowerDistributionClient: TestDependencyKey, Sendable {
    public var powerInfoChanges: @Sendable () -> AsyncStream<PowerDistributionInfo>

    /// One reading, for a caller that needs the answer now rather than a stream of them.
    ///
    /// The SMC is the only source that is current: `AppleSmartBattery` — and so
    /// `kIOPSIsChargingKey` and `CHNC` — lags it by ~17s when charging starts, measured
    /// 2026-08-19. `SystemChargeHold` needs the fresh answer, and needs it only in the state it
    /// is about to call a hold, which is why this is a request rather than a subscription.
    public var powerInfo: @Sendable () async throws -> PowerDistributionInfo

    public init(
        powerInfoChanges: @escaping @Sendable () -> AsyncStream<PowerDistributionInfo>,
        powerInfo: @escaping @Sendable () async throws -> PowerDistributionInfo
    ) {
        self.powerInfoChanges = powerInfoChanges
        self.powerInfo = powerInfo
    }

    nonisolated(unsafe) public static var testValue: PowerDistributionClient = unimplemented()
}

public extension DependencyValues {
    var powerDistributionClient: PowerDistributionClient {
        get { self[PowerDistributionClient.self] }
        set { self[PowerDistributionClient.self] = newValue }
    }
}
