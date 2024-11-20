//
//  MenuDelegate.swift
//
//
//  Created by Adam on 06/11/2023.
//

import AppKit
import AsyncAlgorithms
import Clients
import Dependencies

extension MenuDelegate: DependencyKey {
    public static var liveValue: MenuDelegate = {
        let observer = MenuObserver.shared
        let md = MenuDelegate {
            observer.$menuIsOpened.values.eraseToStream()
        }
        return md
    }()
}
