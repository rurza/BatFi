//
//  LocalizationFallbackTests.swift
//  BatFi
//
//  A missing translation must show the English text, never the raw key.
//

import Foundation
import Testing

@testable import L10n
import Shared

/// Every string in `L10n` is looked up with a `defaultValue`, and Foundation returns that
/// English default whenever the user's language has no entry for the key. It does **not**
/// fall back to `en.lproj` first, so the default is the whole safety net.
///
/// The net has a hole. For a key whose `extractionState` is `manual` and whose English
/// value holds a format specifier (`%@`, `%lld`, …), `xcstringstool` writes the key
/// *as its own value* into every language that lacks a translation. The lookup then
/// succeeds, the default is never consulted, and the user reads
/// `app_charging_mode.state.description.system_charging_past_limit`. That is what a
/// Simplified Chinese user saw on 4.0.2. Keys marked `extracted_with_value` (what Xcode
/// itself records for a `String(localized:defaultValue:)` call) are left out instead.
@Suite struct LocalizationFallbackTests {
    /// What actually ships: no table in the built bundle maps a key to itself.
    @Test func noShippedLocalizationResolvesAKeyToItself() throws {
        let bundle = Bundle.module
        let localizations = bundle.localizations.filter { $0 != "Base" }
        #expect(localizations.count > 1)

        var selfMapped: [String] = []
        for localization in localizations {
            let path = try #require(
                bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: localization)
            )
            let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            selfMapped += table.filter { $0.key == $0.value }.map { "\(localization): \($0.key)" }
        }
        #expect(selfMapped.sorted() == [])
    }

    /// The same, for any translation that goes missing later: compile the catalog with
    /// every translation removed and check that no language falls back to the key.
    @Test func aMissingTranslationNeverResolvesAKeyToItself() async throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/L10n/Localizable.xcstrings")
            .standardizedFileURL
        var catalog = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        var strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let sourceLanguage = try #require(catalog["sourceLanguage"] as? String)

        var languages = Set<String>()
        for (key, var entry) in strings {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            languages.formUnion(localizations.keys)
            entry["localizations"] = localizations.filter { $0.key == sourceLanguage }
            strings[key] = entry
        }
        languages.remove(sourceLanguage)
        #expect(!languages.isEmpty)

        // One fully translated key, so that every language still gets a table.
        let sentinel = "__every_language_sentinel__"
        strings[sentinel] = [
            "localizations": Dictionary(uniqueKeysWithValues: (languages.sorted() + [sourceLanguage]).map {
                ($0, ["stringUnit": ["state": "translated", "value": "x"]])
            }),
        ]
        catalog["strings"] = strings

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalizationFallbackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let strippedURL = directory.appendingPathComponent("Localizable.xcstrings")
        try JSONSerialization.data(withJSONObject: catalog).write(to: strippedURL)

        let output = await Subprocess.standardOutput(
            of: "/usr/bin/xcrun",
            arguments: ["xcstringstool", "compile", "--output-directory", directory.path, strippedURL.path],
            timeout: .seconds(60)
        )
        try #require(output != nil, "xcstringstool compile failed")

        var selfMapped = Set<String>()
        for language in languages {
            let tableURL = directory.appendingPathComponent("\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            selfMapped.formUnion(table.filter { $0.key == $0.value }.map(\.key))
        }
        #expect(selfMapped.sorted() == [])
    }
}
