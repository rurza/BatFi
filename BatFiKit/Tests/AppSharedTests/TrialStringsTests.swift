//
//  TrialStringsTests.swift
//  BatFi
//
//  The menu's trial line counts days with a proper plural.
//

import Foundation
import Testing

@testable import L10n

@Suite struct TrialStringsTests {
    /// The shipped English table, whatever language the Mac running the tests prefers.
    private func english() throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: "en", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test(arguments: [
        (1, "Free trial: 1 day left"),
        (2, "Free trial: 2 days left"),
        (7, "Free trial: 7 days left"),
    ])
    func daysLeftIsPlural(days: Int, text: String) throws {
        #expect(L10n.Trial.daysLeft(days, bundle: try english()) == text)
    }
}
