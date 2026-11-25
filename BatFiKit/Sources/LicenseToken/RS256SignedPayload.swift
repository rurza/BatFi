import Foundation

/// A compact JWS whose payload is plain claims — the form the free trial's statement takes,
/// not the wrapped `k`/`l` form of a licence.
public enum RS256SignedPayload {
    /// The payload's bytes, only once the RS256 signature verifies under the public key in
    /// `publicKeyData`.
    ///
    /// Throws `LicenseTokenError.invalidToken` for a token that is not three base64url
    /// segments with a JSON header, and `.failedVerification` when the signature does not
    /// verify. As for a licence, the protocol fixes the key and RS256; the untrusted header's
    /// `alg` is not consulted.
    public static func verified(_ token: String, publicKeyData: Data) throws -> Data {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3,
              let headerData = RS256Signature.decodeBase64URL(parts[0]),
              (try? JSONDecoder().decode(Header.self, from: headerData)) != nil,
              let payload = RS256Signature.decodeBase64URL(parts[1]) else {
            throw LicenseTokenError.invalidToken
        }
        try RS256Signature.verify(
            encodedHeader: parts[0],
            encodedPayload: parts[1],
            encodedSignature: parts[2],
            publicKeyData: publicKeyData
        )
        return payload
    }
}
