//
//  PreferencesFeature.swift
//
//
//  Created by Adam Różyński on 23/03/2024.
//

import Clients
import ComposableArchitecture
import Foundation

@Reducer
public struct PreferencesFeature: Reducer {
    @ObservableState
    public struct State: Equatable {
        @Shared
        public var automaticallyChecksForUpdates: Bool
        @Shared
        public var automaticallyDownloadsUpdates: Bool

        @Shared(.appStorage("launchAtLogin"))
        public var launchAtLogin = true

        @Shared(.appStorage("forceCharge"))
        public var forceCharge = false

        @Shared(.appStorage("onboardingIsDone"))
        public var onboardingIsDone = false


        // Charging
        @Shared(.appStorage("manageCharging")) 
        public var manageCharging = true

        @Shared(.appStorage("chargeLimit"))
        public var chargeLimit = 80

        @Shared(.appStorage("allowDischargingFullBattery"))
        public var dischargeBatterWhenOvercharged = false


        // Menu bar
        @Shared(.appStorage("showBatteryPercentageInStatusIcon")) 
        public var showBatteryPercentageInStatusIcon = true

        @Shared(.appStorage("monochromeStatusIcon"))
        public var monochromeStatusIcon = true

        @Shared(.appStorage("showChart"))
        public var showChart = false

        @Shared(.appStorage("showPowerDiagram"))
        public var showPowerDiagram = false

        @Shared(.appStorage("showHighEnergyImpactProcesses"))
        public var showHighEnergyImpactProcesses = false

        public var showingHighEnergyImpactSettingsView = false

        // Advanced
        @Shared(.appStorage("downloadBetaVersion")) 
        public var checkForBetaUpdates = false

        @Shared(.appStorage("showDebugMenu"))
        public var showDebugMenu = false

        @Shared(.appStorage("disableSleep"))
        public var disableSleep = false

        @Shared(.appStorage("showGreenLightMagSafeWhenInhibiting"))
        public var magsafeUseGreenLightWhenInhibiting = false

        @Shared(.appStorage("turnOnInhibitingChargingWhenGoingToSleep"))
        public var inhibitChargingOnSleep = false

        @Shared(.appStorage("temperatureSwitch"))
        public var temperatureSwitch = true

        @Shared(.appStorage("turnOnSystemChargeLimitingWhenGoingToSleep"))
        public var enableSystemChargeLimitOnSleep = false


        @Shared(.appStorage("highEnergyImpactProcessesThreshold")) 
        public var highEnergyImpactProcessesThreshold = 500

        @Shared(.appStorage("highEnergyImpactProcessesDuration"))
        public var highEnergyImpactProcessesDuration: TimeInterval = 180

        @Shared(.appStorage("highEnergyImpactProcessesCapacity"))
        public var highEnergyImpactProcessesCapacity = 5


        // notifications
        @Shared(.appStorage("showChargingStausChanged")) 
        public var showChargingStausChanged = true

        @Shared(.appStorage("showOptimizedBatteryCharging"))
        public var showOptimizedBatteryCharging = true

        @Shared(.appStorage("blinkMagSafeWhenDischarging"))
        public var blinkMagSafeWhenDischarging = false

        @Shared(.appStorage("showBatteryLowNotification"))
        public var showBatteryLowNotification = false


        // feature flags
        @Shared(.appStorage("enableHighEnergyImpactProcesses")) 
        public var enableHighEnergyImpactProcesses = false

        @Shared(.appStorage("enablePowerDiagram"))
        public var enablePowerDiagram = false

        public init() {
            self._automaticallyChecksForUpdates = Shared(false)
            self._automaticallyDownloadsUpdates = Shared(false)
        }
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case updateOptions(automaticallyChecksForUpdates: Bool, automaticallyDownloadsUpdates: Bool)
    }

    @Dependency(\.launchAtLogin) var launchAtLogin
    @Dependency(\.updater) private var updater

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.launchAtLogin):
                return .run { [launch = state.launchAtLogin] _ in
                    await launchAtLogin.launchAtLogin(launch)
                }
            case .binding(\.automaticallyChecksForUpdates):
                return .run { [check = state.automaticallyChecksForUpdates] _ in
                    await updater.setAutomaticallyDownloadsUpdates(check)
                }
            case .binding(\.automaticallyDownloadsUpdates):
                return .run { [download = state.automaticallyDownloadsUpdates] _ in
                    await updater.setAutomaticallyDownloadsUpdates(download)
                }
            case .binding(\.checkForBetaUpdates):
                return .run { [beta = state.checkForBetaUpdates] _ in
                    await updater.setAllowBetaVersion(beta)
                }
            case .binding:
                return .none
            case .task:
                return .run { [beta = state.checkForBetaUpdates] send in
                    let automaticallyChecksForUpdates = await updater.automaticallyChecksForUpdates()
                    let automaticallyDownloadsUpdates = await updater.automaticallyDownloadsUpdates()
                    await updater.setAllowBetaVersion(beta)
                    await send(.updateOptions(
                        automaticallyChecksForUpdates: automaticallyChecksForUpdates,
                        automaticallyDownloadsUpdates: automaticallyDownloadsUpdates)
                    )
                }
            case let .updateOptions(automaticallyChecksForUpdates, automaticallyDownloadsUpdates):
                state.automaticallyChecksForUpdates = automaticallyChecksForUpdates
                state.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
                return .none
            }
        }
    }

}
