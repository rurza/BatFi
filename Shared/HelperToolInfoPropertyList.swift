//
//  HelperToolInfoPropertyList.swift
//  SwiftAuthorizationSample
//
//  Created by Josh Kaplan on 2021-10-23
//

import Foundation
import EmbeddedPropertyList

/// Read only representation of the helper tool's info property list.
struct HelperToolInfoPropertyList: Decodable {
    /// Value for `SMAuthorizedClients`.
    let authorizedClients: [String]
    /// Value for `CFBundleVersion`.
    let version: BundleVersion
    /// Value for `CFBundleIdentifier`.
    let bundleIdentifier: String
    
    // Used by the decoder to map the names of the entries in the property list to the property names of this struct
    private enum CodingKeys: String, CodingKey {
        case authorizedClients = "SMAuthorizedClients"
        case version = "CFBundleVersion"
        case bundleIdentifier = "CFBundleIdentifier"
    }
    
    /// An immutable in memory representation of the property list by attempting to read it from the helper tool.
    static var main: HelperToolInfoPropertyList {
        get throws {
            try PropertyListDecoder().decode(HelperToolInfoPropertyList.self,
                                             from: try EmbeddedPropertyListReader.info.readInternal())
        }
    }
    
    /// Creates an immutable in memory representation of the property list by attempting to read it from the helper tool.
    ///
    /// - Parameter url: Location of the helper tool on disk.
    init(from url: URL) throws {
        self = try PropertyListDecoder().decode(HelperToolInfoPropertyList.self,
                                                from: try EmbeddedPropertyListReader.info.readExternal(from: url))
    }
}
