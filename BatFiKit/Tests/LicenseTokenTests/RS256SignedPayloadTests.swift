import Foundation
import Security
import Testing
@testable import LicenseToken

/// The free trial's statement is a compact JWS with plain claims, signed with the licence
/// server's key: its payload is used only when that key's signature verifies.
@Suite
struct RS256SignedPayloadTests {
    private let claims = Data(#"{"app":"BatFi","kind":"trial","computer_id":"3f2b8c1d9e0a4b5c6d7e8f9012345678abcdef0123456789abcdef0123456789","started_at":"2026-11-13T09:30:00Z","ends_at":"2026-11-20T09:30:00Z","confirmed_at":"2026-11-14T08:00:00Z"}"#.utf8)

    @Test
    func aCorrectlySignedTokenGivesItsPayload() throws {
        let key = try fixtureSigningKey()
        let token = try sign(claims, with: key)
        #expect(try RS256SignedPayload.verified(token, publicKeyData: publicKeyData(of: key)) == claims)
    }

    @Test
    func aTamperedPayloadFails() throws {
        let key = try fixtureSigningKey()
        let parts = try sign(claims, with: key).components(separatedBy: ".")
        let tampered = Data(String(decoding: claims, as: UTF8.self)
            .replacingOccurrences(of: "2026-11-20", with: "2027-11-20").utf8)
        let token = [parts[0], base64URL(tampered), parts[2]].joined(separator: ".")
        #expect(throws: LicenseTokenError.failedVerification) {
            try RS256SignedPayload.verified(token, publicKeyData: publicKeyData(of: key))
        }
    }

    @Test
    func aTamperedSignatureFails() throws {
        let key = try fixtureSigningKey()
        let parts = try sign(claims, with: key).components(separatedBy: ".")
        var signature = try #require(decodeBase64URL(parts[2]))
        signature[signature.startIndex] ^= 0x01
        let token = [parts[0], parts[1], base64URL(signature)].joined(separator: ".")
        #expect(throws: LicenseTokenError.failedVerification) {
            try RS256SignedPayload.verified(token, publicKeyData: publicKeyData(of: key))
        }
    }

    @Test
    func aTokenSignedByAnotherKeyFails() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        let otherKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let token = try sign(claims, with: otherKey)
        #expect(throws: LicenseTokenError.failedVerification) {
            try RS256SignedPayload.verified(token, publicKeyData: publicKeyData(of: fixtureSigningKey()))
        }
    }

    @Test
    func twoSegmentsFail() throws {
        let key = try fixtureSigningKey()
        let parts = try sign(claims, with: key).components(separatedBy: ".")
        #expect(throws: LicenseTokenError.invalidToken) {
            try RS256SignedPayload.verified(parts[0] + "." + parts[1], publicKeyData: publicKeyData(of: key))
        }
    }

    @Test
    func fourSegmentsFail() throws {
        let key = try fixtureSigningKey()
        let token = try sign(claims, with: key) + "." + base64URL(Data("extra".utf8))
        #expect(throws: LicenseTokenError.invalidToken) {
            try RS256SignedPayload.verified(token, publicKeyData: publicKeyData(of: key))
        }
    }

    @Test(arguments: ["", "garbage", "a.b.c", "!!!.???.***", "e30.e30.e30"])
    func garbageFails(token: String) throws {
        let key = try fixtureSigningKey()
        #expect(throws: LicenseTokenError.self) {
            try RS256SignedPayload.verified(token, publicKeyData: publicKeyData(of: key))
        }
    }

    // MARK: Signing, as the server does

    /// The synthetic private key the legacy fixture already carries in its claims.
    private func fixtureSigningKey() throws -> SecKey {
        let url = try #require(Bundle.module.url(
            forResource: "legacy-tokens", withExtension: "json", subdirectory: "Fixtures"
        ))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let keyData = try #require(Data(base64Encoded: fixture.claims.k))
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        return try #require(SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil))
    }

    private func publicKeyData(of privateKey: SecKey) throws -> Data {
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        return try #require(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
    }

    private func sign(_ payload: Data, with key: SecKey) throws -> String {
        let header = base64URL(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
        let signingInput = header + "." + base64URL(payload)
        let signature = try #require(SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256, Data(signingInput.utf8) as CFData, nil
        )) as Data
        return signingInput + "." + base64URL(signature)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        let padding = (4 - value.count % 4) % 4
        return Data(base64Encoded: value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: padding))
    }

    private struct Fixture: Decodable {
        let claims: Claims

        struct Claims: Decodable {
            let k: String
        }
    }
}
