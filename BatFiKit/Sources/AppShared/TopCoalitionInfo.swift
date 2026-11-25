import AppKit

public struct TopCoalitionInfo: Equatable, CustomStringConvertible, Sendable {
    public let topCoalitions: [Coalition]

    public init(topCoalitions: [Coalition]) {
        self.topCoalitions = topCoalitions
    }

    public var description: String { "\(topCoalitions)" }

    /// The list without the apps that have quit. The report sums energy over the last few
    /// minutes, so an app that quit is still in it until its use ages out. Only an app — an
    /// entry with a bundle to find it by — can be seen not running; a daemon or a system
    /// coalition stays, since nothing says whether it is still alive.
    public func droppingQuitApps() -> TopCoalitionInfo {
        TopCoalitionInfo(topCoalitions: topCoalitions.filter { $0.isRunning || $0.bundleURL == nil })
    }

    /// Keep the energy ranking within each group, but fill the visible list with apps that
    /// can be slowed down before using its remaining slots for other energy users.
    public func prioritizingSlowable(capacity: Int) -> TopCoalitionInfo {
        let slowable = topCoalitions.filter(\.canSlowDown)
        let others = topCoalitions.filter { !$0.canSlowDown }
        return TopCoalitionInfo(topCoalitions: Array((slowable + others).prefix(max(0, capacity))))
    }

    /// The list with the app shown as no longer running, for an app seen to quit before the
    /// next report of the list arrives. The next report replaces it.
    public func markingNotRunning(_ bundleID: String) -> TopCoalitionInfo {
        TopCoalitionInfo(topCoalitions: topCoalitions.map { coalition in
            guard coalition.bundleIdentifier == bundleID else { return coalition }
            return Coalition(
                bundleIdentifier: coalition.bundleIdentifier,
                energyImpact: coalition.energyImpact,
                icon: coalition.icon,
                displayName: coalition.displayName,
                bundleURL: coalition.bundleURL,
                isRunning: false,
                canOfferActions: coalition.canOfferActions,
                canSlowDown: coalition.canSlowDown
            )
        })
    }
}

public struct Coalition: Equatable, CustomStringConvertible, @unchecked Sendable {
    public let bundleIdentifier: String
    public let energyImpact: Double
    public let icon: NSImage?
    public let displayName: String?
    /// Where the app is: the running copy's bundle where the app is running, otherwise the
    /// copy Launch Services would open. Nil where neither could be found.
    public let bundleURL: URL?
    /// Whether any instance of the app is running now. The list covers the last few minutes,
    /// so it can show an app that has since quit.
    public let isRunning: Bool
    /// Whether the app is one BatFi acts on at all — not a part of macOS, nor BatFi — and so
    /// gets Quit while it runs; see `ThrottleEligibility.canOfferActions` and `canQuit`.
    public let canOfferActions: Bool
    /// Whether the row offers the tortoise, "Slow down on battery": an eligible app that
    /// shows in the Dock; see `ThrottleEligibility.canSlowDown`.
    public let canSlowDown: Bool

    public init(
        bundleIdentifier: String,
        energyImpact: Double,
        icon: NSImage?,
        displayName: String?,
        bundleURL: URL?,
        isRunning: Bool,
        canOfferActions: Bool,
        canSlowDown: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.energyImpact = energyImpact
        self.icon = icon
        self.displayName = displayName
        self.bundleURL = bundleURL
        self.isRunning = isRunning
        self.canOfferActions = canOfferActions
        self.canSlowDown = canSlowDown
    }

    public var description: String {
        "display name: \(displayName ?? bundleIdentifier), energy impact: \(energyImpact), running: \(isRunning), actions: \(canOfferActions), slowable: \(canSlowDown)"
    }

    /// How much energy the app used, as the row shows it: a gauge, not a number.
    public enum EnergyLevel: Equatable, Sendable {
        case medium
        case high
        case veryHigh
        case batteryDraining

        public init(energyImpact: Double) {
            self = switch energyImpact {
            case 0 ..< 300: .medium
            case 300 ..< 900: .high
            case 900 ..< 2000: .veryHigh
            default: .batteryDraining
            }
        }
    }

    public var energyLevel: EnergyLevel { EnergyLevel(energyImpact: energyImpact) }

    /// The same where the row would look and act the same, so that a report of the list that
    /// changes nothing on screen is not published — or logged — again.
    ///
    /// Not the icon: each report looks it up again, and `NSWorkspace` answers a new image
    /// object every time, which `NSImage` compares by identity. Nor the exact energy impact,
    /// which moves on every report while the row shows only its level.
    public static func == (lhs: Coalition, rhs: Coalition) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.displayName == rhs.displayName
            && lhs.bundleURL == rhs.bundleURL
            && lhs.energyLevel == rhs.energyLevel
            && lhs.isRunning == rhs.isRunning
            && lhs.canOfferActions == rhs.canOfferActions
            && lhs.canSlowDown == rhs.canSlowDown
    }
}
