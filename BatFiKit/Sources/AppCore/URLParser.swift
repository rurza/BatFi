//
//  URLParser.swift
//  BatFiKit
//
//  Created by Adam Różyński on 29/01/2025.
//

import Foundation
import L10n

public struct URLParser {
    static public func parseURL(_ url: URL) throws -> String {
        // The thrown strings are what the "Can't use this link" alert shows the user, so
        // they are localized rather than the developer-facing shorthand they once were.
        guard url.scheme == "batfi" else { throw L10n.License.errorLinkNotBatFi }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard components?.host == "activate" else { throw L10n.License.errorLinkWrongDestination }

        let queryItems = components?.queryItems

        guard let _ = queryItems?.first(where: { $0.name == "email" })?.value,
              let licenseKey = queryItems?.first(where: { $0.name == "license" })?.value else { throw L10n.License.errorLinkMissingDetails }

        return licenseKey
    }
}
