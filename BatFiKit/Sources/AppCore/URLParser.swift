//
//  URLParser.swift
//  BatFiKit
//
//  Created by Adam Różyński on 29/01/2025.
//

import Foundation

public struct URLParser {
    static public func parseURL(_ url: URL) throws -> (String, String) {
        guard url.scheme == "batfi" else { throw "Wrong schema" }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard components?.host == "activate" else { throw "Wrong path" }

        let queryItems = components?.queryItems

        guard let email = queryItems?.first(where: { $0.name == "email" })?.value,
              let licenseKey = queryItems?.first(where: { $0.name == "license" })?.value else { throw "Wrong query" }

        return (email, licenseKey)
    }
}
