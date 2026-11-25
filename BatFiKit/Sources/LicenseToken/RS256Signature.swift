import Foundation
import Security

/// The RS256 signature check every token from the licence server goes through.
enum RS256Signature {
    /// Throws `LicenseTokenError.failedVerification` unless `encodedSignature` is the RS256
    /// signature of `encodedHeader.encodedPayload` under the public key in `publicKeyData`.
    ///
    /// The original encoded segments are verified, including any base64 padding.
    static func verify(
        encodedHeader: String,
        encodedPayload: String,
        encodedSignature: String,
        publicKeyData: Data
    ) throws {
        guard let signature = decodeBase64URL(encodedSignature) else {
            throw LicenseTokenError.failedVerification
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        guard let key = SecKeyCreateWithData(publicKeyData as CFData, attributes as CFDictionary, nil) else {
            throw LicenseTokenError.failedVerification
        }
        let signingInput = Data((encodedHeader + "." + encodedPayload).utf8)
        guard SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            signature as CFData,
            nil
        ) else {
            throw LicenseTokenError.failedVerification
        }
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        let padding = (4 - value.count % 4) % 4
        return Data(base64Encoded: value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: padding))
    }
}
