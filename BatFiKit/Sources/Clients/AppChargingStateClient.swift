//
//  AppChargingStateClient.swift
//  
//
//  Created by Adam on 16/05/2023.
//

import AppShared
import Dependencies
import Foundation

public struct AppChargingStateClient: TestDependencyKey {

    public var updateChargingStateMode: (_ mode: AppChargingState.Mode) async -> Void
    public var observeChargingStateMode: () -> AsyncStream<AppChargingState.Mode>
    public var updateLidOpenedStatus: (_ opened: Bool) async -> Void
    public var lidOpened: () async -> Bool?
    public var chargingStateMode: () async -> AppChargingState.Mode?

    public init(
        updateChargingStateMode: @escaping (AppChargingState.Mode) async -> Void,
        observeChargingStateMode: @escaping () -> AsyncStream<AppChargingState.Mode>,
        updateLidOpenedStatus: @escaping (_ opened: Bool) async -> Void,
        lidOpened: @escaping () async -> Bool?,
        chargingStateMode: @escaping () async -> AppChargingState.Mode?
    ) {
        self.updateChargingStateMode = updateChargingStateMode
        self.observeChargingStateMode = observeChargingStateMode
        self.updateLidOpenedStatus = updateLidOpenedStatus
        self.lidOpened = lidOpened
        self.chargingStateMode = chargingStateMode
    }

    public static var testValue: AppChargingStateClient = unimplemented()
}

extension DependencyValues {
    public var appChargingState: AppChargingStateClient {
        get { self[AppChargingStateClient.self] }
        set { self[AppChargingStateClient.self] = newValue }
    }
}
