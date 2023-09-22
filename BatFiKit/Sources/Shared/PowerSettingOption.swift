import IOKit.ps

public struct PowerSettingOption: Codable {
    public let settings: [PowerSource: [PowerSetting]]
    
    public init(settings: [PowerSource: [PowerSetting]]) {
        self.settings = settings
    }
}

public struct PowerSource: OptionSet, Hashable, Codable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let battery = Self(rawValue: 1 << 0)
    public static let external = Self(rawValue: 1 << 1)
    public static let all: PowerSource = [battery, external]
}

extension PowerSource {
    public init?(key: String) {
        switch key {
        case kIOPMBatteryPowerKey:
            self = .battery
        case kIOPMACPowerKey:
            self = .external
        default:
            return nil
        }
    }
    
    public var key: String? {
        switch self {
        case .battery:
            return kIOPMBatteryPowerKey
        case .external:
            return kIOPMACPowerKey
        default:
            return nil
        }
    }
}

extension PowerSource {
    public var allValues: [PowerSource] {
        Self.allValues.filter { contains($0) }
    }
    
    public static let allValues = [battery, external]
}

public enum PowerSetting: Codable {
    case powerMode(powerMode: PowerMode)
}

public enum PowerMode: UInt8, Codable {
    case auto = 0
    case low = 1
    case high = 2
}
