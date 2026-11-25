//
//  TrialFingerprint.swift
//  BatFi
//
//  The one-way stand-in for the Mac's serial that the free trial is keyed by.
//

import CryptoKit
import Foundation

/// The Mac's fingerprint for the free trial: the lowercase hex SHA-256 of
/// `BatFi-trial-v1:` followed by the hardware serial.
///
/// The serial itself never leaves the Mac for a trial; the licence server stores only this.
/// The salt keeps it from matching any other hash of the serial, and its version lets a later
/// scheme be told apart.
public enum TrialFingerprint {
    /// 64 lowercase hex characters, the form the licence server accepts.
    public static func of(serial: String) -> String {
        SHA256.hash(data: Data(("BatFi-trial-v1:" + serial).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
