//
//  HelperOwnership.swift
//  BatFi
//
//  Answers the question `SMAppService` refuses to: *whose* helper is the one macOS
//  actually starts?
//
//  A privileged daemon registered through `SMAppService.daemon(plistName:)` is keyed by
//  label — `software.micropixels.BatFi.Helper` — and Background Task Management stores,
//  alongside that label, the bundle that registered it. Every copy of BatFi on the disk
//  registers the same label, so the record can only ever point at one of them. Which one is
//  decided by whichever copy registered first, and nothing in the API surfaces it:
//
//  * `SMAppService.status` reads `.enabled` from every copy, because the record exists.
//  * `register()` returns without error from a copy that did not get the record, because
//    the record it asked for is, by label, already there.
//
//  So an app launched from `~/Downloads`, or a fresh build in DerivedData, believes it
//  installed and owns a helper while launchd keeps starting the binary inside
//  `/Applications/BatFi.app`. That helper answers XPC perfectly well — it is a real,
//  correctly signed BatFi helper — which is why every reachability-based check the app has
//  passes. It is simply the wrong build, driving the SMC on behalf of an app the user is
//  not looking at, and going stale or vanishing the moment that other copy is updated or
//  deleted.
//
//  The identity is therefore established from the outside, from the running process, rather
//  than asked of the helper: see `HelperCodeIdentityInspector`. This file holds only the
//  vocabulary and the comparison, so the rule can be stated and tested without a Mac in a
//  particular state.
//

import Foundation

/// Who a running helper process actually is, as read from its code signature.
public struct HelperCodeIdentity: Sendable, Equatable {
    /// Absolute path of the running binary, canonicalised.
    public let executablePath: String
    /// Code directory hash of the *loaded image*. Distinguishes two builds sitting at the
    /// same path, which a path comparison cannot.
    public let cdHash: String?
    /// `CFBundleVersion` from the binary's embedded property list, for display only.
    public let version: String?
    public let processIdentifier: Int32

    public init(executablePath: String, cdHash: String?, version: String?, processIdentifier: Int32) {
        self.executablePath = executablePath
        self.cdHash = cdHash
        self.version = version
        self.processIdentifier = processIdentifier
    }
}

/// A helper that is running, reachable, correctly signed — and not the one this copy of the
/// app ships.
public struct HelperOwnershipConflict: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The running helper lives inside a different app bundle. Only re-registering
        /// repoints the Background Task Management record; the user cannot fix this from
        /// System Settings, because toggling Login Items re-enables the *same* record.
        case otherBundle
        /// Right path, different build: the app was replaced on disk while its helper kept
        /// running. Asking that process to quit is enough — launchd starts the new binary.
        case staleBinary
    }

    public let kind: Kind
    /// Where the helper that is actually running lives.
    public let runningExecutablePath: String
    /// Where this copy of the app keeps the helper it ships.
    public let expectedExecutablePath: String
    public let runningVersion: String?
    /// The `.app` that owns the running helper, when the path has that shape. This is the
    /// thing worth naming to the user — "BatFi.app in Downloads" means something, a path
    /// ending in `Contents/MacOS/BatFiHelper` does not.
    public let owningAppPath: String?

    public init(
        kind: Kind,
        runningExecutablePath: String,
        expectedExecutablePath: String,
        runningVersion: String?,
        owningAppPath: String?
    ) {
        self.kind = kind
        self.runningExecutablePath = runningExecutablePath
        self.expectedExecutablePath = expectedExecutablePath
        self.runningVersion = runningVersion
        self.owningAppPath = owningAppPath
    }
}

public enum HelperOwnership: Sendable, Equatable {
    /// The running helper is this copy's own binary.
    case ours
    case foreign(HelperOwnershipConflict)
    /// No verdict could be reached — the process could not be inspected, or its signature
    /// could not be read. Deliberately *not* folded into `.foreign`: the recovery for a
    /// conflict is a re-registration that costs the user a System Settings approval, and
    /// guessing at it on missing evidence is how a working install gets broken.
    case undetermined(String)
}

public enum HelperOwnershipCheck {
    /// Canonicalises a path for comparison.
    ///
    /// Only the transformations that are safe without touching the disk: `/private`
    /// prefixing (`/tmp` vs `/private/tmp`, and `/var` vs `/private/var` — the shape of
    /// every path under a DMG mount or a user's temporary directory), duplicate separators,
    /// and a trailing separator. Symlink resolution is the caller's job, because it is I/O
    /// and this has to stay testable.
    public static func canonicalize(_ path: String) -> String {
        var path = (path as NSString).standardizingPath
        for prefix in ["/private/var/", "/private/tmp/"] where path.hasPrefix(prefix) {
            path = String(path.dropFirst("/private".count))
        }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// The `.app` containing an executable at `.../Something.app/Contents/MacOS/Tool`.
    /// Returns nil for any other shape, rather than inventing one.
    public static func owningAppPath(forExecutableAt path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        // Tool -> MacOS -> Contents -> Something.app
        for _ in 0 ..< 3 {
            url.deleteLastPathComponent()
        }
        guard url.pathExtension == "app" else { return nil }
        return url.path
    }

    /// The whole rule, in one place.
    ///
    /// - Parameters:
    ///   - running: identity of the process currently answering as the helper, or nil when
    ///     it could not be read.
    ///   - expectedExecutablePath: where this copy of the app keeps its helper.
    ///   - expectedCDHash: code directory hash of the helper this copy ships, or nil when
    ///     it could not be read — in which case staleness is simply not tested, because a
    ///     missing hash proves nothing about the running one.
    public static func evaluate(
        running: HelperCodeIdentity?,
        expectedExecutablePath: String,
        expectedCDHash: String?
    ) -> HelperOwnership {
        guard let running else {
            return .undetermined("The helper process could not be identified")
        }
        let runningPath = canonicalize(running.executablePath)
        let expectedPath = canonicalize(expectedExecutablePath)

        if runningPath != expectedPath {
            return .foreign(
                HelperOwnershipConflict(
                    kind: .otherBundle,
                    runningExecutablePath: runningPath,
                    expectedExecutablePath: expectedPath,
                    runningVersion: running.version,
                    owningAppPath: owningAppPath(forExecutableAt: runningPath)
                )
            )
        }

        // Same path. The only remaining way to be the wrong helper is to be the wrong build
        // of it, which the loaded image's hash settles exactly — and which no version string
        // can, since this project pins `CFBundleVersion` to a constant on purpose.
        if let expectedCDHash, let runningHash = running.cdHash, runningHash != expectedCDHash {
            return .foreign(
                HelperOwnershipConflict(
                    kind: .staleBinary,
                    runningExecutablePath: runningPath,
                    expectedExecutablePath: expectedPath,
                    runningVersion: running.version,
                    owningAppPath: owningAppPath(forExecutableAt: runningPath)
                )
            )
        }

        return .ours
    }
}
