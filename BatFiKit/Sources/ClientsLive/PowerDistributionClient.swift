import AppShared
import Clients
import Dependencies
import os
import SwiftyXPC
import Shared

extension PowerDistributionClient: DependencyKey {
    public static var liveValue: PowerDistributionClient = {
        let logger = Logger(category: "Power distribution")

        @Sendable func powerInfo() async throws -> PowerInfo {
            try await XPCClient.shared.sendMessage(.powerInfo)
        }

        let client = Self(
            powerInfoChanges: {
                AsyncStream { continuation in
                    let task = Task {
                        var prevInfo: PowerInfo?
                        while !Task.isCancelled {
                            if let info = try? await powerInfo(), info != prevInfo {
                                logger.notice("New power info: \(info, privacy: .public)")
                                continuation.yield(info)
                                prevInfo = info
                            }
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                    continuation.onTermination = { _ in
                        logger.notice("terminating power info stream")
                        task.cancel()
                    }
                }
            }
        )
        return client
    }()
}
