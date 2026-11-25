//
//  LicenceRecheck.swift
//  BatFi
//
//  What a failed re-check of a stored licence does to it.
//

import Foundation

/// The licence server answered a check with something other than a licence.
///
/// The live client throws it so that a caller can tell a definite "no" from any other
/// failure, while the message shown for a key entered by hand stays the localized one it
/// carries.
public struct LicenceCheckFailure: LocalizedError, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The server does not know the key (HTTP 404).
        case unknownKey
        /// The server knows the key and says it was deactivated (HTTP 403).
        case deactivated
        /// Any other status that is not 200.
        case unexpectedStatus(Int)

        /// The failure an HTTP status is, or nil for 200.
        public init?(status: Int) {
            switch status {
            case 200: return nil
            case 404: self = .unknownKey
            case 403: self = .deactivated
            default: self = .unexpectedStatus(status)
            }
        }
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// The periodic re-check of a licence already stored on this Mac.
///
/// Only a definite answer from the server gives the licence up: the key is unknown, or it
/// was deactivated. Everything else — a server error, rate limiting, a reply that cannot be
/// read or whose signature fails, a timeout, no network, an unreadable serial number — says
/// nothing about the licence. Giving it up then would hand charging back to macOS and let the
/// energy features go for a paying customer over a licence server or Gumroad outage, so the
/// licence is kept and the re-check is tried again on a later launch.
public enum LicenceRecheck {
    public static func givesUpStoredLicence(after error: any Error) -> Bool {
        guard let failure = error as? LicenceCheckFailure else { return false }
        switch failure.kind {
        case .unknownKey, .deactivated:
            return true
        case .unexpectedStatus:
            return false
        }
    }

    /// The licence model's state once a re-check of `storedLicence` failed with `error`.
    public static func state<Licence>(
        after error: any Error,
        storedLicence: Licence
    ) -> AsyncResource<Licence?> {
        givesUpStoredLicence(after: error) ? .error(error as NSError) : .loaded(storedLicence)
    }
}
