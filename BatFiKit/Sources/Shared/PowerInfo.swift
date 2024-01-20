import Foundation

public struct PowerInfo: Codable, Equatable, CustomStringConvertible {
    public let batteryPower: Float
    public let externalPower: Float
    public let systemPower: Float

    public init(batteryPower: Float, externalPower: Float, systemPower: Float) {
        self.batteryPower = batteryPower
        self.externalPower = externalPower
        self.systemPower = systemPower
    }

    public var description: String {
        "Battery power: \(batteryPower), external power: \(externalPower), system power: \(systemPower)"
    }
}
