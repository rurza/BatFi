//
//  Route.swift
//  
//
//  Created by Adam on 14/04/2023.
//

import SecureXPC

public extension XPCRoute {
    static let uninstall = Self.named("XPCRouteWithoutMessageWithoutReply")
}

public enum Route {
    public static let uninstall = XPCRoute.named("uninstall")
    
}

