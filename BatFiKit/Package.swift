// swift-tools-version: 5.9

import PackageDescription

extension Target.Dependency {
    static let aboutKit: Self = .product(name: "AboutKit", package: "AboutKit")
    static let appShared: Self = "AppShared"
    static let asyncAlgorithms: Self = .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
    static let asyncXPCConnection: Self = .product(name: "AsyncXPCConnection", package: "AsyncXPCConnection")
    static let clients: Self = "Clients"
    static let confetti: Self = .product(name: "ConfettiSwiftUI", package: "ConfettiSwiftUI")
    static let defaults: Self = .product(name: "Defaults", package: "Defaults")
    static let defaultsKeys: Self = "DefaultsKeys"
    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let dependenciesMacros: Self = .product(name: "DependenciesMacros", package: "swift-dependencies")
    static let embeddedPropertyList: Self = .product(name: "EmbeddedPropertyList", package: "EmbeddedPropertyList")
    static let highEnergyUsage: Self = "HighEnergyUsage"
    static let identifiedCollections: Self = .product(name: "IdentifiedCollections", package: "swift-identified-collections")
    static let jwt: Self = .product(name: "SwiftJWT", package: "Swift-JWT")
    static let keyboardShortcuts: Self = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
    static let l10n: Self = "L10n"
    static let menuBuilder: Self = .product(name: "MenuBuilder", package: "MenuBuilder")
    static let persistence: Self = "Persistence"
    static let powerCharts: Self = "PowerCharts"
    static let powerDistributionInfo: Self = "PowerDistributionInfo"
    static let sentry: Self = .product(name: "Sentry", package: "sentry-cocoa")
    static let settings: Self = "Settings"
    static let settingsKit: Self = .product(name: "SettingsKit", package: "SettingsKit")
    static let shared: Self = "Shared"
    static let sharedUI: Self = "SharedUI"
    static let snapKit: Self = .product(name: "SnapKit", package: "SnapKit")
    static let sparkle: Self = .product(name: "Sparkle", package: "Sparkle")
    static let statusItemArrowKit: Self = .product(name: "StatusItemArrowKit", package: "StatusItemArrowKit")
}

let package = Package(
    name: "BatFiKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "App", targets: ["App"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "AppShared", targets: ["AppShared"]),
        .library(name: "BatteryIndicator", targets: ["BatteryIndicator"]),
        .library(name: "BatteryInfo", targets: ["BatteryInfo"]),
        .library(name: "ClientsLive", targets: ["ClientsLive"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "PowerCharts", targets: ["PowerCharts"]),
        .library(name: "Server", targets: ["Server"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "SharedUI", targets: ["SharedUI"]),
        .library(name: "L10n", targets: ["L10n"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.2.2"),
        .package(url: "https://github.com/trilemma-dev/EmbeddedPropertyList", from: "2.0.0"),
        .package(url: "https://github.com/rurza/SettingsKit.git", branch: "main"),
        .package(url: "https://github.com/rurza/AboutKit.git", branch: "main"),
        .package(url: "https://github.com/sindresorhus/Defaults", branch: "main"),
        .package(url: "https://github.com/j-f1/MenuBuilder", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.3"),
        .package(url: "https://github.com/SnapKit/SnapKit", branch: "main"),
        .package(url: "https://github.com/rurza/StatusItemArrowKit.git", branch: "main"),
        .package(url: "https://github.com/simibac/ConfettiSwiftUI", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.0.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.25.0"),
        .package(url: "https://github.com/ChimeHQ/AsyncXPCConnection", from: "1.1.0"),
        .package(url: "https://github.com/rurza/KeyboardShortcuts", branch: "main"),
        .package(url: "https://github.com/Kitura/Swift-JWT", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "About",
            dependencies: [
                .aboutKit,
                .appShared,
                .l10n,
                .sharedUI,
            ]
        ),
        .target(
            name: "App",
            dependencies: [
                "About",
                "AppCore",
                "BatteryIndicator",
                "BatteryInfo",
                "ClientsLive",
                "Notifications",
                "Onboarding",
                .clients,
                .defaultsKeys,
                .keyboardShortcuts,
                .l10n,
                .menuBuilder,
                .settings,
                .statusItemArrowKit,
            ]
        ),
        .target(name: "AppCore", dependencies: [
            .appShared,
            .asyncAlgorithms,
            "BatteryInfo",
            "BatteryIndicator",
            .clients,
            .defaultsKeys,
            .dependencies,
            .highEnergyUsage,
            .l10n,
            .menuBuilder,
            .powerCharts,
            .powerDistributionInfo,
            .settings,
            .shared,
            .snapKit,
        ]),
        .target(name: "AppShared", dependencies: [.l10n]),
        .target(name: "Shared"),
        .target(
            name: "BatteryIndicator",
            dependencies: [
                .appShared,
                .asyncAlgorithms,
                .clients,
            ]
        ),
        .target(name: "BatteryInfo", dependencies: [
            .appShared,
            .asyncAlgorithms,
            .clients,
            .dependencies,
            .l10n,
        ]),
        .target(
            name: "Clients",
            dependencies: [
                .appShared,
                .defaults,
                .dependencies,
                .dependenciesMacros,
                .shared,
            ]
        ),
        .target(
            name: "ClientsLive",
            dependencies: [
                .appShared,
                .asyncAlgorithms,
                .asyncXPCConnection,
                .clients,
                .defaults,
                .defaultsKeys,
                .dependencies,
                .jwt,
                .persistence,
                .sentry,
                .shared,
                .sparkle,
            ]
        ),
        .target(name: "DefaultsKeys", dependencies: [.defaults]),
        .target(
            name: "HighEnergyUsage",
            dependencies: [
                .asyncAlgorithms,
                .appShared,
                .clients,
                .dependencies,
                .defaults,
                .defaultsKeys,
                .l10n,
                .shared,
            ]
        ),
        .target(
            name: "Notifications",
            dependencies: [
                .appShared,
                .asyncAlgorithms,
                .clients,
                .defaultsKeys,
                .dependencies,
                .l10n,
            ]
        ),
        .target(
            name: "L10n"
        ),
        .target(
            name: "Onboarding",
            dependencies: [
                .appShared,
                .clients,
                .confetti,
                .defaults,
                .defaultsKeys,
                .l10n,
                .sharedUI,
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                .appShared,
                .dependencies,
                .shared,
            ]
        ),
        .target(
            name: "PowerCharts",
            dependencies: [
                .appShared,
                .clients,
                .dependencies,
                .l10n,
                .persistence,
                .identifiedCollections,
            ]
        ),
        .target(name: "PowerDistributionInfo", dependencies: [
            .appShared,
            .clients,
            .dependencies,
            .l10n,
            .shared,
        ]),
        .target(name: "Server", dependencies: [
            .asyncXPCConnection,
            .defaults,
            .defaultsKeys,
            .embeddedPropertyList,
            .sentry,
            .shared,
        ]),
        .target(
            name: "Settings",
            dependencies: [
                .appShared,
                .clients,
                .defaultsKeys,
                .dependencies,
                .keyboardShortcuts,
                .l10n,
                .settingsKit,
                .sharedUI,
            ]
        ),
        .target(name: "SharedUI"),
    ]
)
