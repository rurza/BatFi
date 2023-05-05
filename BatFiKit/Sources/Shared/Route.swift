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
}
