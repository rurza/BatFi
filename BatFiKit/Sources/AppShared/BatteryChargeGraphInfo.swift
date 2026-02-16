import Foundation

public struct BatteryChargeGraphInfo: Equatable, Sendable {
    public let batteryStates: [BatteryState]
    public let chargeLevels: [ChargeLevel]

    public init(batteryStates: [BatteryState], chargeLevels: [ChargeLevel]) {
        self.batteryStates = batteryStates
        self.chargeLevels = chargeLevels
    }
}

public struct BatteryState: Equatable, Sendable {
    public let state: Bool
    public let time: UInt

    public init(state: Bool, time: UInt) {
        self.state = state
        self.time = time
    }
}

public struct ChargeLevel: Equatable, Sendable {
    public let level: UInt8
    public let time: UInt

    public init(level: UInt8, time: UInt) {
        self.level = level
        self.time = time
    }
}
