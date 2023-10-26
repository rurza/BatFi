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
        @Dependency(\.powerInfoClient) private var powerInfoClient

        @Published
        private(set) var powerInfo: PowerInfo?
        private var powerInfoChanges: Task<(), Never>?

        init() { }

        func startObserving() {
            powerInfoChanges = Task {
                for await info in powerInfoClient.powerInfoChanges() {
                    self.powerInfo = info
                }
            }
        }

        func cancelObserving() {
            powerInfoChanges?.cancel()
            powerInfo = nil
        }
    }
}
