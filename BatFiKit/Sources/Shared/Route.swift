//
//  Route.swift
//  Helper
//
//  Created by Adam on 24/04/2023.
//

import SecureXPC

public extension XPCRoute {
    static let charging = Self.named("charging")
        .withMessageType(SMCChargingCommand.self)
        .throwsType(SMCError.self)

    static let smcStatus = Self.named("smcStatus")
        .withMessageType(SMCStatusCommand.self)
        .withReplyType(SMCStatus.self)
        .throwsType(SMCError.self)

    static let quit = Self.named("quit")

    static let magSafeLEDColor = Self.named("magSafeLEDColor")
        .withMessageType(MagSafeLEDOption.self)
        .withReplyType(MagSafeLEDOption.self)
        .throwsType(SMCError.self)
    
    static let powerInfo = Self.named("powerInfo")
        .withReplyType(PowerInfo.self)
        .throwsType(SMCError.self)
}
