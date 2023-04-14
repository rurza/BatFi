//
//  Route.swift
//  
//
//  Created by Adam on 14/04/2023.
//

import SecureXPC

public let route = XPCRoute.named("")
    .withMessageType(String.self)
    .withReplyType(Bool.self)
