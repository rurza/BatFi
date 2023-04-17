//
//  SMCCommand.swift
//  BatFi
//
//  Created by Adam on 16/04/2023.
//

import Foundation

enum SMCCommand: Codable {
    case enableCharging
    case disableCharging
}

/// Errors that prevent an allowed command from being run.
enum SMCCommandError: Error, Codable {
    /// The user did not grant authorization.
    case authorizationFailed
    /// The client did not request authorization, but it was required.
    case authorizationNotRequested
}
