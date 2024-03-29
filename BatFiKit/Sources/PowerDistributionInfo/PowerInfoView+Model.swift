//
//  PowerInfoView+Model.swift
//
//
//  Created by Adam on 14/10/2023.
//

import Clients
import Combine
import Dependencies
import Shared

extension PowerInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerDistributionClient) private var powerInfoClient
        @Dependency(\.menuDelegate) private var menuDelegate

        @Published
        private(set) var powerInfo: PowerDistributionInfo?
        private var powerInfoChanges: Task<Void, Never>?
        private var menuChanges: Task<Void, Never>?

        init() {
            menuChanges = Task { [weak self] in
                if let observeMenu = await self?.menuDelegate.observeMenu() {
                    for await menuIsVisible in observeMenu {
                        if menuIsVisible {
                            self?.startObserving()
                        } else {
                            self?.cancelObserving()
                        }
                    }
                }
            }
        }

        private func startObserving() {
            powerInfoChanges = Task { [weak self] in
                guard let self else { return }
                for await info in powerInfoClient.powerInfoChanges() {
                    powerInfo = info
                }
            }
        }

        private func cancelObserving() {
            powerInfoChanges?.cancel()
            powerInfo = nil
        }

        deinit {
            powerInfoChanges?.cancel()
            menuChanges?.cancel()
        }
    }
}
