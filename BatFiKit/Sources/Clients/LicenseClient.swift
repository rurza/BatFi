import Dependencies
import Foundation

public struct LicenseClient: TestDependencyKey {
    public var checkLicense: (_ email: String, _ key: String) async throws -> License

    init(checkLicense: @escaping (String, String) async throws -> License) {
        self.checkLicense = checkLicense
    }

    public static var testValue: LicenseClient = unimplemented()
}

public struct License: Codable, Equatable {
    public let key: String
    public let name: String?
    public let email: String
    public let purchaseDate: Date
}
