//
//  TrialRequest.swift
//  BatFi
//
//  What the app asks the licence server for a free trial, before encryption.
//

import Foundation

/// The body of `POST /trial` before it is encrypted: the app's name and the Mac's
/// fingerprint, nothing else (the free-trial wire spec).
public enum TrialRequest {
    /// The app's name exactly as the licence server's `apps` table has it.
    public static let app = "BatFi"

    public static func body(fingerprint: String) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Two string fields cannot fail to encode.
        return try! encoder.encode(Body(app: app, computerID: fingerprint))
    }

    private struct Body: Encodable {
        let app: String
        let computerID: String

        private enum CodingKeys: String, CodingKey {
            case app
            case computerID = "computer_id"
        }
    }
}
