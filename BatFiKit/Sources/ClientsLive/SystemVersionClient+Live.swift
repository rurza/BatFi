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
        Self(
            currentSystemIsSequoiaOrNewer: {
                ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
            }
        )
    }()
}

