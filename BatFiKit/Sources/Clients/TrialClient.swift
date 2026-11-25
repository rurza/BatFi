import Dependencies
import DependenciesMacros
import Foundation
import Shared

/// The seven-day free trial, as the licence server states it and the keychain keeps it.
@DependencyClient
public struct TrialClient: TestDependencyKey, Sendable {
    /// Asks the licence server for this Mac's trial — starting it the first time, reporting
    /// it afterwards — and stores the signed statement it answers with. Throws a
    /// `TrialRequestFailure`, after which nothing has been stored.
    public var requestTrial: @Sendable () async throws -> TrialStatement
    /// The stored statement, or nil when none is stored or the stored one no longer verifies
    /// or decodes. Throws when the keychain could not be read: the trial is then not known.
    public var storedTrial: @Sendable () async throws -> TrialStatement?
    /// Removes the stored statement.
    public var forgetTrial: @Sendable () async throws -> Void
    /// This Mac's fingerprint, which a stored statement is judged against; nil when the
    /// hardware serial cannot be read. Never sent anywhere by itself.
    public var fingerprint: @Sendable () -> String?
    nonisolated(unsafe) public static var testValue: TrialClient = unimplemented()
}

public extension DependencyValues {
    var trialClient: TrialClient {
        get { self[TrialClient.self] }
        set { self[TrialClient.self] = newValue }
    }
}
