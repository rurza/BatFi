import AppKit

public struct TopCoalitionInfo: Equatable, CustomStringConvertible {
    public let topCoalitions: [Coalition]

    public init(topCoalitions: [Coalition]) {
        self.topCoalitions = topCoalitions
    }

    public var description: String { "\(topCoalitions)" }
}

public struct Coalition: Equatable, CustomStringConvertible {
    public let bundleIdentifier: String
    public let energyImpact: Double
    public let icon: NSImage?
    public let displayName: String?

    public init(bundleIdentifier: String, energyImpact: Double, icon: NSImage?, displayName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.energyImpact = energyImpact
        self.icon = icon
        self.displayName = displayName
    }

    public var description: String { "display name: \(displayName ?? bundleIdentifier), energy impact: \(energyImpact)" }
}
