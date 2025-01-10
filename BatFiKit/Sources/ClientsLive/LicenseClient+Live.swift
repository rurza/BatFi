//
//  LicenseClient+Live.swift
//  BatFiKit
//
//  Created by Adam Różyński on 29.12.2024.
//

import Clients
import Dependencies
import Foundation
import IOKit
import os.log
import Shared
import SwiftJWT

extension LicenseClient: DependencyKey {
    public static var liveValue: LicenseClient = {
        let logger = Logger(category: "LicenseClient")

        @inline(never)
        func url() -> URL {
            URL(string: "https://" + "license" + "." + "batfi" + "." + "micropixels" + "." + "software" + "/" + "verify")!
        }

        struct Claims: SwiftJWT.Claims {
            let k: String
            let l: String
        }

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "BatFi"]
        let session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return LicenseClient(
            checkLicense: { email, key in
                guard let serialNumber = getSystemSerialNumber() else {
                    throw "Can't identify system"
                }
                let licenseRequest = LicenseRequest(email: email, key: key, id: serialNumber)

                var request = URLRequest(
                    url: url(),
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 20
                )
                request.httpMethod = "POST"

                let publicKeyData = loadPublicKey()
                let options: [String: Any] = [
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass as String: kSecAttrKeyClassPublic
                ]
                var error: Unmanaged<CFError>?
                guard let publicKey = SecKeyCreateWithData(publicKeyData as CFData, options as CFDictionary, &error) else {
                    fatalError("Failed to create SecKey from public key data, error: \(String(describing: error?.takeRetainedValue()))")
                }
                let requestBody = try JSONEncoder().encode(licenseRequest)
                let encryptedRequestBody = try encryptRSA(data: requestBody, key: publicKey)
                let base64EncodedBody = encryptedRequestBody.base64EncodedString()
                request.httpBody = base64EncodedBody.data(using: .utf8)

                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw "Invalid response"
                }
                guard httpResponse.statusCode != 404 else {
                    throw "Invalid license"
                }
                guard httpResponse.statusCode != 403 else {
                    throw "License is deactivated"
                }
                guard httpResponse.statusCode == 200 else {
                    throw "Unexpected response"
                }
                guard let jwtString = String(data: data, encoding: .utf8) else {
                    throw "Unexpected response"
                }
                let rsaJWTDecoder = JWTDecoder(jwtVerifier: JWTVerifier.rs256(publicKey: publicKeyData))
                let jwt = try rsaJWTDecoder.decode(JWT<Claims>.self, fromString: jwtString)
                guard let privateKeyData = Data(base64Encoded: jwt.claims.k) else {
                    throw "Unexpected response"
                }
                let privateKey = try createSecKey(from: privateKeyData)

                guard let encryptedLicenseData = Data(base64Encoded: jwt.claims.l) else {
                    throw "Unexpected response"
                }
                let decryptedLicenseData = try decryptRSA(data: encryptedLicenseData, privateKey: privateKey)
                let license = try decoder.decode(License.self, from: decryptedLicenseData)
                return license
            }
        )
    }()
}

private func createSecKey(from privateKeyData: Data) throws -> SecKey {
    let options: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
    ]
    guard let privateKey = SecKeyCreateWithData(privateKeyData as CFData, options as CFDictionary, nil) else {
        throw "Failed to create SecKey"
    }
    return privateKey
}

private func decryptRSA(data: Data, privateKey: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let decryptedData = SecKeyCreateDecryptedData(
        privateKey,
        .rsaEncryptionPKCS1,
        data as CFData,
        &error
    ) else {
        throw error?.takeRetainedValue() as Error? ?? "Decryption failed"
    }
    return decryptedData as Data
}

private func encryptRSA(data: Data, key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let encryptedData = SecKeyCreateEncryptedData(
        key,
        .rsaEncryptionPKCS1,
        data as CFData,
        &error
    ) else {
        throw error?.takeRetainedValue() as Error? ?? "Encryption failed"
    }
    return encryptedData as Data
}

extension License: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let email = try container.decode(String.self, forKey: .email)
        let key = try container.decode(String.self, forKey: .key)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let purchaseDate = try container.decode(Date.self, forKey: .purchaseDate)
        self.init(key: key, name: name, email: email, purchaseDate: purchaseDate)
    }
    
    private enum CodingKeys: String, CodingKey {
        case email
        case key
        case name = "customer_name"
        case purchaseDate = "purchase_date"
    }
}


struct LicenseRequest: Encodable {
    let email: String
    let key: String
    let id: String
}

func getSystemSerialNumber() -> String? {
    let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard platformExpert != 0 else { return nil }
    defer { IOObjectRelease(platformExpert) }

    guard let serialNumber = IORegistryEntryCreateCFProperty(
        platformExpert,
        kIOPlatformSerialNumberKey as CFString,
        kCFAllocatorDefault,
        0
    )?.takeUnretainedValue() as? String else {
        return nil
    }
    return serialNumber
}

private func loadPublicKey() -> Data {
    guard let publicKeyURL = Bundle.module.url(forResource: "key", withExtension: "der") else {
        fatalError("Couldn't find public key file at \(String(describing: Bundle.module.resourceURL)).key.der")
    }
    return try! Data(contentsOf: publicKeyURL)
}
