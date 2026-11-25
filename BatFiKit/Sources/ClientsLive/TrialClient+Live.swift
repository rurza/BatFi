import AppShared
import Clients
import Dependencies
import Foundation
import LicenseToken
import os.log
import Shared

extension TrialClient: DependencyKey {
    nonisolated(unsafe) public static var liveValue: TrialClient = {
        let logger = Logger(category: "TrialClient")

        @Sendable @inline(never)
        func url() -> URL {
            URL(string: "https://" + "license" + "." + "batfi" + "." + "micropixels" + "." + "software" + "/" + "trial")!
        }

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "BatFi"]
        let session = URLSession(configuration: config)

        @Dependency(\.keychainClient) var keychainClient
        let publicKeyData = loadPublicKey()

        @Sendable func verify(_ token: String) throws -> Data {
            try RS256SignedPayload.verified(token, publicKeyData: publicKeyData)
        }

        @Sendable func ask() async throws(TrialRequestFailure) -> TrialReply {
            do {
                guard let serialNumber = getSystemSerialNumber() else { throw TrialRequestFailure.unavailable }
                let fingerprint = TrialFingerprint.of(serial: serialNumber)

                let options: [String: Any] = [
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                ]
                guard let publicKey = SecKeyCreateWithData(publicKeyData as CFData, options as CFDictionary, nil) else {
                    throw TrialRequestFailure.unavailable
                }
                let body = try encryptRSA(data: TrialRequest.body(fingerprint: fingerprint), key: publicKey)

                var request = URLRequest(url: url(), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.httpMethod = "POST"
                request.httpBody = Data(body.base64EncodedString().utf8)

                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { throw TrialRequestFailure.unavailable }
                return try TrialReply(status: httpResponse.statusCode, body: data, fingerprint: fingerprint, verify: verify)
            } catch {
                logger.error("Trial request failed: \(error.localizedDescription, privacy: .public)")
                throw TrialRequestFailure(error)
            }
        }

        return TrialClient(
            requestTrial: {
                let reply = try await ask()
                do {
                    try await keychainClient.saveTrial(reply.token)
                } catch {
                    logger.error("Could not save trial to keychain: \(error.localizedDescription, privacy: .public)")
                }
                return reply.statement
            },
            storedTrial: {
                guard let token = try await keychainClient.getTrial() else { return nil }
                return TrialReply.storedStatement(token: token, verify: verify)
            },
            forgetTrial: {
                try await keychainClient.saveTrial(nil)
            },
            fingerprint: {
                getSystemSerialNumber().map(TrialFingerprint.of(serial:))
            }
        )
    }()
}
