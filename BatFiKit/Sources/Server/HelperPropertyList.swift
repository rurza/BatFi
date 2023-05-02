//
//  HelperPropertyList.swift
//  Helper
//
//  Created by Adam on 25/04/2023.
//

import EmbeddedPropertyList
import Foundation

struct HelperPropertyList: Decodable {
    public let bundleIdentifier: String
    public let authorizedClients: [String]

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "CFBundleVersion"
        case authorizedClients = "SMAuthorizedClients"
    }
}
