//
//  LaunchAtLogin.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Clients
import Dependencies
import Foundation
import ServiceManagement

extension LaunchAtLogin: DependencyKey {
    public static let liveValue: LaunchAtLogin = {
        let client = LaunchAtLogin(
            launchAtLogin: { launchAtLogin in
                if launchAtLogin {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
        )
        return client
    }()
}
