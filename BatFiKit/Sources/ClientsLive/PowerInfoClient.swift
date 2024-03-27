import AppShared
import Clients
import Dependencies
import os
import SecureXPC
import Shared

extension PowerInfoClient: DependencyKey {
    public static var liveValue: PowerInfoClient = {
        @Sendable func createClient() -> XPCClient {
            XPCClient.forMachService(
                named: Constant.helperBundleIdentifier,
                withServerRequirement: try! .sameTeamIdentifier
            )
        }
        let logger = Logger(category: "Power distribution")

        @Sendable func powerInfo() async throws -> PowerInfo {
            try await createClient().send(to: XPCRoute.powerInfo)
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
