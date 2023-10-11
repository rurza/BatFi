import AppKit

public struct TopCoalitionInfo: Equatable {
    public let topCoalitions: [Coalition]
    
    public init(topCoalitions: [Coalition]) {
        self.topCoalitions = topCoalitions
    }
}

public struct Coalition: Equatable {
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
}
