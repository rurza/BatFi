import Foundation
import Security

/// The verified claims needed to decrypt a BatFi license.
public struct RS256LicenseToken: Sendable {
    public let privateKey: String
    public let encryptedLicense: String

    public init(_ token: String, publicKeyData: Data) throws {
        let parts = token.components(separatedBy: ".")
        guard parts.count > 1,
              let headerData = RS256Signature.decodeBase64URL(parts[0]),
              let payloadData = RS256Signature.decodeBase64URL(parts[1]) else {
            throw LicenseTokenError.invalidToken
        }

        let decoder = JSONDecoder()
        _ = try decoder.decode(Header.self, from: headerData)
        let claims = try decoder.decode(Claims.self, from: payloadData)

        guard parts.count == 3 else {
            throw LicenseTokenError.failedVerification
        }
        // The license protocol fixes both the key and RS256 independently of the
        // untrusted header, matching the previous decoder.
        try RS256Signature.verify(
            encodedHeader: parts[0],
            encodedPayload: parts[1],
            encodedSignature: parts[2],
            publicKeyData: publicKeyData
        )

        privateKey = claims.k
        encryptedLicense = claims.l
    }
}

// Preserve the previous decoder's type checks for recognized header fields.
struct Header: Decodable {
    let typ: String?
    let alg: String?
    let jku: String?
    let jwk: String?
    let kid: String?
    let x5u: String?
    let x5c: [String]?
    let x5t: String?
    let x5tS256: String?
    let cty: String?
    let crit: [String]?
}

private struct Claims: Decodable {
    let k: String
    let l: String
    // Standard time claims remain unused: the decrypted license's refresh date
    // controls renewal, as it did with Swift-JWT.
}

enum LicenseTokenError: LocalizedError, Equatable {
    case invalidToken
    case failedVerification

    var errorDescription: String? {
        // Keep the messages previously surfaced by Swift-JWT.
        switch self {
        case .invalidToken: "Input was not a valid JWT String"
        case .failedVerification: "JWT verifier failed to verify the JWT String signiture"
        }
    }
}
