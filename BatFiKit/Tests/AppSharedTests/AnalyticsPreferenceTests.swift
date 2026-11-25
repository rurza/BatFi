import Defaults
import DefaultsKeys
import Foundation
import Shared
import Testing

@Suite
final class AnalyticsPreferenceTests {
    private let suiteName = "AnalyticsPreferenceTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func matchesAppPreferenceIncludingLegacyValues() {
        let values: [Any?] = [
            nil, true, false,
            NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: 2),
            "true", "false", " false\n", "FALSE", "NO", "YES", "0", "1", "",
            [true], ["value": false],
        ]
        for value in values {
            defaults.set(value, forKey: AnalyticsPreference.name)
            #expect(
                AnalyticsPreference.read(from: defaults) == defaults[.sendAnalytics],
                Comment(rawValue: "Stored value: \(String(describing: value))")
            )
        }
    }

    @Test
    func defaultsToDisabledAndHonorsOptIn() {
        #expect(!AnalyticsPreference.read(from: defaults))
        #expect(!defaults[.sendAnalytics])
        defaults.set(true, forKey: AnalyticsPreference.name)
        #expect(AnalyticsPreference.read(from: defaults))
        defaults.set("true", forKey: AnalyticsPreference.name)
        #expect(AnalyticsPreference.read(from: defaults))
        defaults.set(false, forKey: AnalyticsPreference.name)
        #expect(!AnalyticsPreference.read(from: defaults))
    }

    @Test
    func betaBuildsStartCrashReportingWhateverThePreference() {
        #expect(AnalyticsPreference.shouldStartCrashReporting(isBeta: true, defaults: defaults))
        defaults.set(false, forKey: AnalyticsPreference.name)
        #expect(AnalyticsPreference.shouldStartCrashReporting(isBeta: true, defaults: defaults))
    }

    @Test
    func nonBetaBuildsStartCrashReportingOnlyAfterOptIn() {
        #expect(!AnalyticsPreference.shouldStartCrashReporting(isBeta: false, defaults: defaults))
        defaults.set(true, forKey: AnalyticsPreference.name)
        #expect(AnalyticsPreference.shouldStartCrashReporting(isBeta: false, defaults: defaults))
    }
}
