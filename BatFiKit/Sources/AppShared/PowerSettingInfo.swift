import Shared

public struct PowerSettingInfo {
    public let powerMode: PowerMode
    public let supportsHighPowerMode: Bool
    
    public init(powerMode: PowerMode, supportsHighPowerMode: Bool) {
        self.powerMode = powerMode
        self.supportsHighPowerMode = supportsHighPowerMode
    }
}
