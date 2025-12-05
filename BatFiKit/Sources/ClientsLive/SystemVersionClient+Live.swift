//
//  SystemVersionClient.swift
//  BatFiKit
//
//  Created by Adam Różyński on 12/08/2024.
//

import AppKit
import Clients
import Dependencies

extension SystemVersionClient: DependencyKey {
    public static let liveValue: Self = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Self(
            currentSystemIsSequoiaOrNewer: {
                version.majorVersion >= 15
            },
            currentSystemIsTahoeOrNewer: {
                // macOS 26 (Tahoe) introduced SMC key lockdown
                version.majorVersion >= 26
            },
            majorVersion: {
                version.majorVersion
            }
        )
    }()
}

