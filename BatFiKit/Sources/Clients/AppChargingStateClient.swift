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

    public var updateChargingStateMode: (_ mode: AppChargingMode) async -> Void
    public var observeChargingStateMode: () -> AsyncStream<AppChargingMode>
    public var updateLidOpenedStatus: (_ opened: Bool) async -> Void
    public var lidOpened: () async -> Bool?
    public var chargingStateMode: () async -> AppChargingMode?

    public init(
        updateChargingStateMode: @escaping (AppChargingMode) async -> Void,
        observeChargingStateMode: @escaping () -> AsyncStream<AppChargingMode>,
        updateLidOpenedStatus: @escaping (_ opened: Bool) async -> Void,
        lidOpened: @escaping () async -> Bool?,
        chargingStateMode: @escaping () async -> AppChargingMode?
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
