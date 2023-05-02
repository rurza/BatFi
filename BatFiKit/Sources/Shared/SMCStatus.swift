//
//  SMCStatus.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Foundation

public struct SMCStatus: Codable {
    public let forceCharging: Bool
    public let inhitbitCharging: Bool
    public let lidClosed: Bool

    public init(
        forceCharging: Bool,
        inhitbitCharging: Bool,
        lidClosed: Bool
    ) {
        self.forceCharging = forceCharging
        self.inhitbitCharging = inhitbitCharging
        self.lidClosed = lidClosed
    }

}
