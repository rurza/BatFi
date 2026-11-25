//
//  LicenceForTrial.swift
//  BatFi
//
//  What the free trial is told about the licence.
//

import Foundation

/// What the free trial is told about the licence.
///
/// The trial asks the server only when told no valid licence is held (see
/// `TrialStatus.asksServerAgain`), so "not valid" is said only where the app knows it: nothing
/// is stored, or the stored licence was ruled out. A licensed Mac's fingerprint is never sent
/// for a trial.
public enum LicenceForTrial {
    /// True while a valid licence is held; false where none is; nil while not known.
    ///
    /// `storedLicenceRuledOut` says the stored licence was found in this run not to be a valid
    /// licence: its re-check got a definite "no" from the server, the server returned a licence
    /// for another key, or the stored item cannot be turned into a licence. Short of that, a
    /// stored licence not held as valid is one not judged yet — its re-check still running —
    /// and may well be valid: a key typed and refused meanwhile says nothing about it.
    public static func isValid(
        licenceIsHeld: Bool,
        storedLicence: StoredLicence,
        storedLicenceRuledOut: Bool
    ) -> Bool? {
        if licenceIsHeld { return true }
        switch storedLicence {
        case .notKnown:
            return nil
        case .none:
            return false
        case .present:
            return storedLicenceRuledOut ? false : nil
        }
    }
}
