import AppShared
import Clients
import Dependencies
import os
import Shared

extension PowerDistributionClient: DependencyKey {
    public static var liveValue: PowerDistributionClient = {

        @Sendable func powerInfo() async throws -> PowerDistributionInfo {
            return try await XPCClient.shared.getPowerDistribution()
        }

        let client = Self(
            powerInfoChanges: {
                AsyncStream { continuation in
                    let task = Task {
                        var prevInfo: PowerDistributionInfo?
                        while !Task.isCancelled {
                            if let info = try? await powerInfo(), info != prevInfo {
                                continuation.yield(info)
                                prevInfo = info
                            }
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            }
        )
        return client
    }()
}
