//
//  Constants.swift
//  
//
//  Created by Adam on 14/04/2023.
//

import SecureXPC

extension XPCRoute {
    static let charging = Self.named("charging")
        .withMessageType(SMCChargingCommand.self)
}

let helperBundleIdentifier = "software.micropixels.BatFi.Helper"
let helperPlistName = helperBundleIdentifier + ".plist"
