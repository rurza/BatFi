import Foundation

public class PowerDistributionInfo: NSObject, Codable, NSSecureCoding {
    public static var supportsSecureCoding: Bool = true

    public let batteryPower: Float
    public let externalPower: Float
    public let systemPower: Float

    public init(batteryPower: Float, externalPower: Float, systemPower: Float) {
        self.batteryPower = batteryPower
        self.externalPower = externalPower
        self.systemPower = systemPower
        super.init()
    }

    public override var description: String {
        "Battery power: \(batteryPower), external power: \(externalPower), system power: \(systemPower)"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(batteryPower, forKey: "batteryPower")
        coder.encode(externalPower, forKey: "externalPower")
        coder.encode(systemPower, forKey: "systemPower")
    }

    public required init?(coder: NSCoder) {
        batteryPower = coder.decodeFloat(forKey: "batteryPower")
        externalPower = coder.decodeFloat(forKey: "externalPower")
        systemPower = coder.decodeFloat(forKey: "systemPower")
        super.init()
    }
}
