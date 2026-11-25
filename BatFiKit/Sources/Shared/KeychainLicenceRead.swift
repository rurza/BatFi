//
//  KeychainLicenceRead.swift
//  BatFi
//
//  What a keychain read of the licence item answers.
//

import Foundation
import Security

/// Turns the result of reading the licence item from the keychain into an answer.
///
/// Only a missing item means there is no licence. Every other failure — a locked keychain,
/// interaction not allowed, a denied prompt — says nothing about whether one is stored, and
/// throws, so the licence stays unknown rather than being recorded as absent: recorded as
/// absent, charge management, Low Power Mode and app throttling all hand back over a
/// licence that is still there.
public enum KeychainLicenceRead {
    /// The keychain could not be read; whether a licence is stored is not known.
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let status: OSStatus

        public init(status: OSStatus) {
            self.status = status
        }

        public var description: String {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain read failed: \(status) (\(message))"
        }
    }

    /// The licence string, nil when none is stored, or a thrown `Failure` when the keychain
    /// could not say.
    ///
    /// An item that is there but is not UTF-8 text is not a usable licence, and reading it
    /// again will not change that, so it is reported as none.
    public static func result(status: OSStatus, data: Data?) throws -> String? {
        switch status {
        case errSecSuccess:
            guard let data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }
}
