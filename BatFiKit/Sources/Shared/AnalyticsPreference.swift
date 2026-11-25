import Foundation

public enum AnalyticsPreference {
    public static let name = "sendAnalytics"
    public static let defaultValue = false

    public static func read(from defaults: UserDefaults) -> Bool {
        let rawValue = defaults.object(forKey: name)
        if let value = rawValue as? Bool {
            return value
        }
        // Match Defaults' Codable bridge for previously stored JSON booleans.
        if let string = rawValue as? String,
           let value = try? JSONDecoder().decode(Bool.self, from: Data(string.utf8)) {
            return value
        }
        return defaultValue
    }

    /// Beta builds always send crash reports; other builds only after the user opts in.
    public static func shouldStartCrashReporting(isBeta: Bool, defaults: UserDefaults) -> Bool {
        isBeta || read(from: defaults)
    }
}
