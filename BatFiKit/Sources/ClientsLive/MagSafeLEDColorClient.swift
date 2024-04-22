//
//  MagSafeLEDColorClient.swift
//
//
//  Created by Adam on 16/07/2023.
//

import Clients
import Dependencies
import Foundation
import Shared

extension MagSafeLEDColorClient: DependencyKey {
    public static var liveValue: MagSafeLEDColorClient = {
        let client = Self(
            changeMagSafeLEDColor: { (option: MagSafeLEDOption) in
                return try await XPCClient.shared.changeMagSafeLEDColor(option)
            },
            currentMagSafeLEDOption: {
                return try await XPCClient.shared.currentMagSafeLEDOption()
            }
        )
        return client
    }()
}
