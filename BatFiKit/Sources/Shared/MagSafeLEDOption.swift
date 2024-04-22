//
//  MagSafeLEDOption.swift
//
//
//  Created by Adam on 16/07/2023.
//

import Foundation

public enum MagSafeLEDOption: UInt8, Codable, CustomStringConvertible {
    case reset = 0
    case off = 1
    case green = 3
    case orange = 4
    case errorOnce = 5
    case errorPermamently = 6

    public var description: String {
        switch self {
        case .reset:
            return "Reset"
        case .off:
            return "Off"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        case .errorOnce:
            return "Error Once"
        case .errorPermamently:
            return "Error Permamently"
        }
    }
}
