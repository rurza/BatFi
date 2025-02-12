//
//  Error+String.swift
//  BatFiKit
//
//  Created by Adam Różyński on 29.12.2024.
//

import Foundation

extension String: LocalizedError {
    public var errorDescription: String? { self }
}
