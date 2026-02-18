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

@MainActor
final class PowerInfoViewModel: ObservableObject {
    @Dependency(\.powerDistributionClient) private var powerInfoClient
    @Dependency(\.menuDelegate) private var menuDelegate

    @Published
    private(set) var powerInfo: PowerDistributionInfo?
    private var powerInfoChanges: Task<Void, Never>?
    private var menuChanges: Task<Void, Never>?

    init() {
        print("🟢 PowerInfoViewModel init")
        menuChanges = Task { [weak self] in
            guard let menuDelegate = self?.menuDelegate else { return }
            for await menuIsVisible in await menuDelegate.observeMenu() {
                guard let self else { break }
                if menuIsVisible {
                    self.startObserving()
                } else {
                    self.cancelObserving()
                }
            }
        }
    }

    private func startObserving() {
        powerInfoChanges = Task { [weak self] in
            guard let powerInfoClient = self?.powerInfoClient else { return }
            for await info in powerInfoClient.powerInfoChanges() {
                guard let self else { break }
                self.powerInfo = info
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
        print("🔴 PowerInfoViewModel deinit")
    }
}
