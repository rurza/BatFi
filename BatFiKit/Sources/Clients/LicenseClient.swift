import Dependencies
import Foundation
import DependenciesMacros

@DependencyClient
public struct LicenseClient: TestDependencyKey, Sendable {
    public var checkLicense: @Sendable (_ key: String) async throws -> License
    public var cachedLicense: @Sendable () async throws -> License?
    nonisolated(unsafe) public static var testValue: LicenseClient = unimplemented()
}

public struct License: Equatable, Sendable {
    public let key: String
    public let name: String?
    public let email: String
    public let purchaseDate: Date
    public let refreshDate: Date

    public init(key: String, name: String?, email: String, purchaseDate: Date, refreshDate: Date) {
        self.key = key
        self.name = name
        self.email = email
        self.purchaseDate = purchaseDate
        self.refreshDate = refreshDate
    }
}

public extension DependencyValues {
    var licenseClient: LicenseClient {
        get { self[LicenseClient.self] }
        set { self[LicenseClient.self] = newValue }
    }
}
