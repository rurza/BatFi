//
//  LicenseStatus+Trial.swift
//  BatFi
//
//  A running free trial unlocks the app as a licence does.
//

import Foundation

extension LicenseStatus {
    /// What the features act on, from the licence and the trial: valid when either the licence
    /// is valid or the trial is running; otherwise unknown while either is still not known;
    /// otherwise invalid.
    ///
    /// `licence` is the licence alone, read with `reading(_:)`. The features keep the meaning
    /// they had: a trial not read yet beside a licence known not to be valid is unknown, so
    /// nothing held is given back at launch for a trial that may be running, and a licence not
    /// read yet beside an ended trial is unknown too, as it always was.
    public static func unlocking(licence: LicenseStatus, trial: TrialStatus) -> LicenseStatus {
        if licence == .valid { return .valid }
        if case .running = trial { return .valid }
        if licence == .unknown || trial == .notKnown { return .unknown }
        return .invalid
    }
}
