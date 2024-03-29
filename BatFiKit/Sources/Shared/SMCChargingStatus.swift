//
//  SMCChargingStatus.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Foundation

public class SMCChargingStatus: NSObject, Codable, NSSecureCoding {
    public static var supportsSecureCoding: Bool = true

    public func encode(with coder: NSCoder) {
        coder.encode(forceDischarging, forKey: "forceDischarging")
        coder.encode(inhitbitCharging, forKey: "inhitbitCharging")
        coder.encode(lidClosed, forKey: "lidClosed")
    }

    public required init?(coder: NSCoder) {
        forceDischarging = coder.decodeBool(forKey: "forceDischarging")
        inhitbitCharging = coder.decodeBool(forKey: "inhitbitCharging")
        lidClosed = coder.decodeBool(forKey: "lidClosed")
        super.init()
    }

    public let forceDischarging: Bool
    public let inhitbitCharging: Bool
    public let lidClosed: Bool

    public init(
        forceDischarging: Bool,
        inhitbitCharging: Bool,
        lidClosed: Bool
    ) {
        self.forceDischarging = forceDischarging
        self.inhitbitCharging = inhitbitCharging
        self.lidClosed = lidClosed
        super.init()
    }

    public override var description: String {
        """
        Status:
        forceDischarging: \(forceDischarging)
        inhitbitCharging: \(inhitbitCharging)
        lidClosed: \(lidClosed)
        """
    }
}
