//
//  HelperPropertyList.swift
//  Helper
//
//  Created by Adam on 25/04/2023.
//

import EmbeddedPropertyList
import Foundation

struct HelperPropertyList: Decodable {
    public let build: String
    public let version: String
    public let authorizedClients: [String]

    private enum CodingKeys: String, CodingKey {
        case version = "CFBundleShortVersionString"
        case build = "CFBundleVersion"
        case authorizedClients = "SMAuthorizedClients"
    }
}
