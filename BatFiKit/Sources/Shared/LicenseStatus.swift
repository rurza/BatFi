//
//  LicenseStatus.swift
//  BatFi
//
//  What the energy features — automatic Low Power Mode and slowing apps down on battery —
//  know of the app licence. Without a valid one they stop and give back what they hold,
//  exactly as charge management does.
//

import Foundation

/// The app licence as the energy features act on it.
///
/// Three states rather than `LicenseModel.hasValidLicense`'s two, because of launch: the
/// features start before the licence has been read from the keychain, and a feature still
/// holding something an earlier run left — Low Power Mode kept through a crash, say — must
/// not give it back only to take it again a moment later, when the read finishes.
public enum LicenseStatus: Equatable, Sendable {
    /// Not read yet in this run. Nothing new is taken on, and nothing held is given back for
    /// it.
    case unknown
    case valid
    /// Read, and not valid: there is none, it was rejected or removed, or it could not be
    /// checked.
    case invalid

    /// Whether a feature may take something new on: turn Low Power Mode on, slow an app down.
    public var allowsTakingOn: Bool { self == .valid }

    /// Whether a feature may keep what it already holds. Only a licence known not to be valid
    /// takes it away.
    public var allowsHolding: Bool { self != .invalid }

    /// What charge management does with the licence on a pass.
    public enum ChargeManagement: Equatable, Sendable {
        /// Apply the limit and decide the mode.
        case manage
        /// Neither apply nor hand back; the licence arriving drives the next pass.
        case waitForLicence
        /// Hand charging back to macOS, releasing BatFi's limit.
        case handBack
    }

    /// The same rule the energy features follow, applied to charge management. Handing back
    /// on a licence not read yet is what released BatFi's limit at launch: the first passes
    /// run before the keychain read finishes, and on macOS 27 below 80% the limit applied
    /// again a moment later pays powerd's adoption wait — up to 45 s, with the charger in.
    public var chargeManagement: ChargeManagement {
        if !allowsHolding { return .handBack }
        return allowsTakingOn ? .manage : .waitForLicence
    }

    /// The status once the licence model reports `state`.
    ///
    /// The model's `.initial` and `.loading` say nothing by themselves. At launch it is
    /// `.initial` until the keychain has been read, and `.loading` while a key is checked, so
    /// until the first answer the licence stays unknown. After that, the model going back to
    /// `.initial` means the licence was removed or an error dismissed, and it checks a key only
    /// when it holds no valid licence — both are "not valid", never unknown again.
    public func reading<Resource>(_ state: AsyncResource<Resource?>) -> LicenseStatus {
        switch state {
        case .loaded(.some):
            .valid
        case .loaded(.none), .error:
            .invalid
        case .initial, .loading:
            self == .unknown ? .unknown : .invalid
        }
    }
}
