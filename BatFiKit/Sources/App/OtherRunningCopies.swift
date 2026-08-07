//
//  OtherRunningCopies.swift
//  BatFi
//
//  Finds the *other* BatFi.
//
//  Two copies of the app can be open at once — macOS only enforces one instance per bundle
//  *path*, not per bundle identifier, so `/Applications/BatFi.app` and a build in DerivedData
//  or a copy in `~/Downloads` run happily side by side. They then share one daemon label,
//  and each sees the other's helper as foreign.
//
//  This exists so that the ownership recovery can decline in that case. It is the one
//  situation where taking the record is not a repair: the other copy takes it straight back,
//  and the user is left with a helper that belongs to whichever app last won a race they
//  cannot see. Telling them which other copy is open is the only move that ends anywhere.
//

import AppKit
import Foundation
import Shared

enum OtherRunningCopies {
    struct Copy: Sendable {
        let path: String
        let processIdentifier: pid_t
    }

    /// Any running BatFi that is not this process, or nil when this is the only one.
    ///
    /// Matched on bundle identifier and separated by bundle URL rather than by pid alone:
    /// a second copy is the same identifier at a different path, which is exactly what
    /// `NSRunningApplication` lets us see and `SMAppService` does not.
    @MainActor
    static func first() -> Copy? {
        let ourselves = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let ourPID = ProcessInfo.processInfo.processIdentifier

        return NSRunningApplication
            .runningApplications(withBundleIdentifier: Constant.appBundleIdentifier)
            .lazy
            .filter { $0.processIdentifier != ourPID }
            .compactMap { application -> Copy? in
                guard let url = application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL,
                      url != ourselves else { return nil }
                return Copy(path: url.path, processIdentifier: application.processIdentifier)
            }
            .first
    }
}
