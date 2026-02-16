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
    nonisolated(unsafe) public static var liveValue: MenuDelegate = {
        let md = MenuDelegate {
            await MainActor.run {
                MenuObserver.shared.$menuIsOpened.values.eraseToStream()
            }
        }
        return md
    }()
}
