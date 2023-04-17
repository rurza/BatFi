//
//  HelperToolPropertyList.swift
//  BatFi
//
//  Created by Adam on 17/04/2023.
//

import Foundation

/// Read only representation of the helper tool's property list.
struct HelperToolPropertyList: Decodable {
    /// Value for `Label`.
    let label: String
    /// Value for `MachServices`.
    let machServices: [String: Bool]


    // Used by the decoder to map the names of the entries in the property list to the property names of this struct
    private enum CodingKeys: String, CodingKey {
        case label = "Label"
        case machServices = "MachServices"
    }

    /// An immutable in memory representation of the property list by attempting to read it from the helper tool.
    static var main: HelperToolPropertyList {
        get throws {
            let bundleIdentifier = Bundle.main.bundleIdentifier! + ".Helper"
            let url = Bundle.main.url(forResource: bundleIdentifier, withExtension: "plist")!
            let plist = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(
                HelperToolPropertyList.self,
                from: plist
            )
        }
    }

}
