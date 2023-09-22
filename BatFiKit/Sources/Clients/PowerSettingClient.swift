import AppShared
import Dependencies
import Shared

public struct PowerSettingClient: TestDependencyKey {
    public var powerSettingInfoChanges: () -> AsyncStream<PowerSettingInfo>
    public var setPowerMode: (PowerMode, PowerSource) async throws -> Void
    
    public init(
        powerSettingInfoChanges: @escaping () -> AsyncStream<PowerSettingInfo>,
        setPowerMode: @escaping (PowerMode, PowerSource) async throws -> Void
    ) {
        self.powerSettingInfoChanges = powerSettingInfoChanges
        self.setPowerMode = setPowerMode
    }
    
    public static var testValue: PowerSettingClient = unimplemented()
}

extension DependencyValues {
    public var powerSettingClient: PowerSettingClient {
        get { self[PowerSettingClient.self] }
        set { self[PowerSettingClient.self] = newValue }
    }
}
