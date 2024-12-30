import Dependencies
import Foundation
import DependenciesMacros

@DependencyClient
public struct LicenseClient: TestDependencyKey {
    public var checkLicense: (_ email: String, _ key: String) async throws -> License

    public static var testValue: LicenseClient = unimplemented()
}

public struct License: Equatable {
    public let key: String
    public let name: String?
    public let email: String
    public let purchaseDate: Date

    public init(key: String, name: String?, email: String, purchaseDate: Date) {
        self.key = key
        self.name = name
        self.email = email
        self.purchaseDate = purchaseDate
    }
}

public extension DependencyValues {
    var licenseClient: LicenseClient {
        get { self[LicenseClient.self] }
        set { self[LicenseClient.self] = newValue }
    }
}
