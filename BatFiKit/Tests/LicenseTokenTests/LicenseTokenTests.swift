import Foundation
import Security
import Testing
@testable import LicenseToken

@Suite
struct LicenseTokenTests {
    @Test
    func matchesLegacyDecoder() throws {
        let fixture = try loadFixture()
        for test in fixture.cases {
            let publicKey = try #require(Data(base64Encoded: test.publicKey))
            let result = Result { try RS256LicenseToken(test.token, publicKeyData: publicKey) }
            switch result {
            case .success(let token):
                #expect(test.accepted, Comment(rawValue: test.name))
                #expect(token.privateKey == fixture.claims.k, Comment(rawValue: test.name))
                #expect(token.encryptedLicense == fixture.claims.l, Comment(rawValue: test.name))
            case .failure:
                #expect(!test.accepted, Comment(rawValue: test.name))
            }
        }
    }

    @Test
    func verifiedClaimsDecryptLicense() throws {
        let fixture = try loadFixture()
        let validCase = fixture.cases.first { $0.accepted }
        let test = try #require(validCase)
        let publicKey = try #require(Data(base64Encoded: test.publicKey))
        let token = try RS256LicenseToken(test.token, publicKeyData: publicKey)
        let privateKeyData = try #require(Data(base64Encoded: token.privateKey))
        let encryptedLicense = try #require(Data(base64Encoded: token.encryptedLicense))
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        let key = try #require(SecKeyCreateWithData(privateKeyData as CFData, attributes as CFDictionary, nil))
        let decrypted = try #require(SecKeyCreateDecryptedData(
            key, .rsaEncryptionPKCS1, encryptedLicense as CFData, nil
        )) as Data
        #expect(decrypted == Data(fixture.licenseJSON.utf8))
    }

    @Test
    func preservesErrorMessages() throws {
        #expect(throws: LicenseTokenError.invalidToken) {
            try RS256LicenseToken("invalid", publicKeyData: Data())
        }
        let fixture = try loadFixture()
        let validCase = fixture.cases.first { $0.accepted }
        let test = try #require(validCase)
        #expect(throws: LicenseTokenError.failedVerification) {
            try RS256LicenseToken(test.token, publicKeyData: Data())
        }
        #expect(LicenseTokenError.invalidToken.localizedDescription == "Input was not a valid JWT String")
        #expect(LicenseTokenError.failedVerification.localizedDescription == "JWT verifier failed to verify the JWT String signiture")
    }

    private func loadFixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(
            forResource: "legacy-tokens", withExtension: "json", subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

// Synthetic keys and licenses only. Acceptance expectations were captured from
// Swift-JWT 4.0.2 before removing it, including malformed, tampered and expired
// tokens, alternate headers, padding, wrong keys and unsupported signatures.
private struct Fixture: Decodable {
    let claims: Claims
    let licenseJSON: String
    let cases: [Case]

    struct Claims: Decodable {
        let k: String
        let l: String
    }

    struct Case: Decodable {
        let name: String
        let token: String
        let publicKey: String
        let accepted: Bool
    }
}
