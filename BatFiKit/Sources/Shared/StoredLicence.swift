//
//  StoredLicence.swift
//  BatFi
//
//  Whether a licence is stored on this Mac, apart from whether it is valid.
//

import Foundation

/// Whether a licence is stored on this Mac, whatever its validity.
///
/// The licence model's state says whether a valid licence is held, and "no" covers a keychain
/// not read yet, a keychain that could not be read, a stored licence whose re-check failed and
/// a key being checked. A paying customer can be in any of those. This answers only what is
/// stored, and says `none` only where the app knows nothing is: the keychain was read and was
/// empty, or the licence was deleted from it.
public enum StoredLicence: Equatable, Sendable {
    /// The keychain has not been read in this run, or could not be read.
    case notKnown
    /// Nothing is stored.
    case none
    /// A licence is stored, whether or not it is currently confirmed valid.
    case present

    /// What the licence model learned about the keychain.
    public enum Event: Equatable, Sendable {
        /// The keychain was read. An item that is there but cannot be turned into a licence is
        /// still found: it is stored.
        case keychainRead(found: Bool)
        /// The keychain could not be read; that says nothing about what is stored.
        case keychainUnreadable
        /// The re-check of a stored licence failed. The licence stays in the keychain, even
        /// when the server's answer ends in the model's error state.
        case recheckFailed
        /// A key entered by hand is being checked.
        case verificationStarted
        /// A key entered by hand was checked and stored.
        case keyVerified
        /// A key entered by hand was not accepted; nothing was stored.
        case verificationFailed
        /// The user dismissed the error a failed check showed.
        case errorDismissed
        /// The licence was deleted from the keychain: the user removed it, or a re-check
        /// returned a licence for another key.
        case deleted
        /// The keychain refused to delete the licence, so it is still stored.
        case deletionFailed
    }

    /// The answer once `event` happened. Once known it never goes back to `notKnown`.
    public func after(_ event: Event) -> StoredLicence {
        switch event {
        case .keychainRead(let found):
            found ? .present : .none
        case .keyVerified:
            .present
        case .deleted:
            .none
        case .keychainUnreadable, .recheckFailed, .verificationStarted, .verificationFailed,
             .errorDismissed, .deletionFailed:
            self
        }
    }
}
