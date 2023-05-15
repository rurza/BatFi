//
//  AppChargingState.swift
//  
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public actor AppChargingState: ObservableObject {

    public private(set) var mode: Mode? {
        didSet { // we want the didSet, so we can read from the object
            objectWillChange.send()
        }
    }
    public private(set) var lidOpened: Bool? {
        didSet {
            objectWillChange.send()
        }
    }

    public static let shared = AppChargingState(mode: nil, lidOpened: nil)

    public init(mode: Mode?, lidOpened: Bool?) {
        self.mode = mode
        self.lidOpened = lidOpened
    }

    public func updateMode(_ mode: Mode) {
        self.mode = mode
    }

    public func updateLidOpened(_ lidOpened: Bool) {
        self.lidOpened = lidOpened
    }

    public enum Mode {
        case charging
        case inhibit
        case forceDischarge
        case forceCharge
        case disabled
    }
}
