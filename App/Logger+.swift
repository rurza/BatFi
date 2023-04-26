//
//  Logger+.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Foundation
import os

extension Logger {
    init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier!, category: category)
    }
}
