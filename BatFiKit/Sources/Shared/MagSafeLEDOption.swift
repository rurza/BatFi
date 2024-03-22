//
//  MagSafeLEDOption.swift
//
//
//  Created by Adam on 16/07/2023.
//

import Foundation

public enum MagSafeLEDOption: UInt8, Codable {
    case reset = 0
    case off = 1
    case green = 3
    case orange = 4
    case errorOnce = 5
    case errorPermamently = 6
}
