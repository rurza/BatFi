//
//  Constants.swift
//  
//
//  Created by Adam on 14/04/2023.
//

import SecureXPC

extension XPCRoute {
    static let battery = Self.named("battery")
        .withMessageType(SMCCommand.self)
        .withReplyType(Bool.self)
        .throwsType(SMCCommandError.self)
}

let helperBundleIdentifier = "software.micropixels.BatFi.Helper"
let helperPlistName = helperBundleIdentifier + ".plist"
