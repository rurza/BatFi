//
//  PowerdChargePolicyTests.swift
//  BatFi
//
//  Reading the limit powerd enforces out of `com.apple.powerd.charging.plist`: a top-level
//  `policies` blob that is itself a keyed-archiver plist, with the charge policy among its
//  objects carrying `soclimit`. The answer to "is the limit in force", as opposed to "was it
//  asked for".
//

import Foundation
import Testing

@testable import Shared

@Suite struct PowerdChargePolicyTests {
    private func plist(policyObjects: [Any]?) throws -> Data {
        var top: [String: Any] = ["somethingElse": 1]
        if let policyObjects {
            let archive: [String: Any] = [
                "$archiver": "NSKeyedArchiver",
                "$objects": policyObjects,
            ]
            top["policies"] = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        }
        return try PropertyListSerialization.data(fromPropertyList: top, format: .xml, options: 0)
    }

    @Test func readsTheEnforcedSocLimit() throws {
        let data = try plist(policyObjects: ["$null", ["drain": true, "soclimit": 77], "ChargeCtrlPolicy"])
        #expect(PowerdChargePolicy.enforcedLimit(plistData: data) == 77)
    }

    /// On battery powerd keeps no charge policy at all.
    @Test func noPolicyIsNoLimit() throws {
        let data = try plist(policyObjects: ["$null"])
        #expect(PowerdChargePolicy.enforcedLimit(plistData: data) == nil)
    }

    @Test func noPoliciesKeyIsNoLimit() throws {
        let data = try plist(policyObjects: nil)
        #expect(PowerdChargePolicy.enforcedLimit(plistData: data) == nil)
    }

    @Test func unreadableDataIsNoLimit() {
        #expect(PowerdChargePolicy.enforcedLimit(plistData: Data("not a plist".utf8)) == nil)
    }
}
