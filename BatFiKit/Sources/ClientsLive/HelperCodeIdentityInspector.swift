//
//  HelperCodeIdentityInspector.swift
//  BatFi
//
//  Reads who the running helper is, from the outside.
//
//  The obvious design — ask the helper over XPC where it lives — was rejected for two
//  reasons, and the second is the one that decided it:
//
//  1. It only works against helpers new enough to answer, and the whole problem is old and
//     foreign copies. A helper from a previous release would fail the call, and "did not
//     answer" is not evidence of anything.
//  2. It is a self-report. The connection already pins the peer to a signature, so a lie is
//     unlikely, but there is no reason to accept a claim when the fact is readable.
//
//  So the identity is taken from the kernel's own view of the process: the connection's pid,
//  through `SecCodeCopyGuestWithAttributes`, to the path and code directory hash of the
//  image that is actually loaded. This works against every helper BatFi has ever shipped,
//  needs nothing from the helper, and cannot be spoofed by it.
//
//  It also needs no privilege — which is not obvious, since the helper runs as root. The
//  Security framework will vend a guest `SecCode` for another user's process to any caller;
//  it is `proc_pidpath`-style introspection that is restricted, and this is not that. The
//  app is not sandboxed, so nothing narrows it further.
//

import AppShared
import Foundation
import os
import Security
import Shared

enum HelperCodeIdentityInspector {
    private static let logger = Logger(category: "Helper Identity")

    /// Where this copy of the app keeps the helper it ships.
    ///
    /// Built from the running bundle rather than from a stored path on purpose: this value
    /// has to follow the app when the user drags it somewhere else, and it is the answer to
    /// "which binary *should* be running", which is by definition this bundle's.
    static var expectedHelperExecutableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent(Constant.helperBundleProgramPath)
    }

    /// Identity of the process behind an XPC connection.
    ///
    /// - Parameter requirement: the same code-signing requirement the connection is pinned
    ///   to. Re-checked here rather than assumed: this lookup is by pid, and a pid is
    ///   reusable, so between the connection being established and this call the number
    ///   could in principle name something else. Validating the signature means the only
    ///   identity this can ever return is a genuine BatFi helper's — a wrong answer becomes
    ///   no answer, which the policy already knows how to treat as no evidence.
    ///
    ///   Passing the *same* requirement the connection is pinned to is what keeps this from
    ///   quietly disabling the check: a helper that satisfies the connection satisfies this,
    ///   so the only builds it can refuse to identify are ones the app could never have been
    ///   talking to in the first place. Development builds included — Xcode signs them with
    ///   the same team, which is all the requirement asks.
    static func identity(ofProcessWithID pid: pid_t, satisfying requirement: String) -> HelperCodeIdentity? {
        guard pid > 0 else {
            logger.warning("No process identifier for the helper connection yet")
            return nil
        }
        guard let code = guestCode(forProcessWithID: pid) else { return nil }
        // `SecCode` is a `SecStaticCode` subtype; the Security functions below document
        // that they accept either, but the Swift interfaces are typed to the static one.
        let asStatic = unsafeBitCast(code, to: SecStaticCode.self)

        var codeRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &codeRequirement) == errSecSuccess,
              let codeRequirement else {
            logger.error("Could not compile the helper code requirement")
            return nil
        }
        let validity = SecCodeCheckValidity(code, [], codeRequirement)
        guard validity == errSecSuccess else {
            logger.error("Helper process \(pid, privacy: .public) does not satisfy the BatFi requirement: \(validity, privacy: .public)")
            return nil
        }

        var url: CFURL?
        guard SecCodeCopyPath(asStatic, [], &url) == errSecSuccess, let path = (url as URL?)?.path else {
            logger.error("Could not read the path of helper process \(pid, privacy: .public)")
            return nil
        }

        let information = signingInformation(of: asStatic)
        return HelperCodeIdentity(
            executablePath: canonicalPath(path),
            cdHash: cdHash(from: information),
            version: version(from: information),
            processIdentifier: pid
        )
    }

    /// Identity of a binary on disk — used for the helper this app ships, so that a stale
    /// process sitting at the right path can be told apart from the current build.
    static func identity(ofFileAt url: URL) -> HelperCodeIdentity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            logger.error("Could not read the signature of the bundled helper at \(url.path, privacy: .public)")
            return nil
        }
        let information = signingInformation(of: staticCode)
        return HelperCodeIdentity(
            executablePath: canonicalPath(url.path),
            cdHash: cdHash(from: information),
            version: version(from: information),
            processIdentifier: 0
        )
    }

    // MARK: - Private

    private static func guestCode(forProcessWithID pid: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let code else {
            logger.error("Could not obtain a code object for process \(pid, privacy: .public): \(status, privacy: .public)")
            return nil
        }
        return code
    }

    private static func signingInformation(of code: SecStaticCode) -> [String: Any] {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    /// Hash of the loaded code directory. Read from the *dynamic* code object where the
    /// caller passed one, which is what makes it able to see a stale process: asking the
    /// file at the same path would return the new build's hash and report agreement.
    private static func cdHash(from information: [String: Any]) -> String? {
        guard let data = information[kSecCodeInfoUnique as String] as? Data else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static func version(from information: [String: Any]) -> String? {
        guard let plist = information[kSecCodeInfoPList as String] as? [String: Any] else { return nil }
        return plist["CFBundleVersion"] as? String ?? plist["CFBundleShortVersionString"] as? String
    }

    /// Resolves symlinks — the I/O half of the comparison, kept out of `HelperOwnershipCheck`
    /// so that the rule itself stays testable — and then applies the pure canonicalisation.
    ///
    /// Worth doing rather than comparing raw strings: `/tmp`, `/var` and every path under a
    /// mounted disk image reach here through at least one link, and an app running from a
    /// still-mounted DMG is one of the ways a user ends up with two copies in the first place.
    private static func canonicalPath(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return HelperOwnershipCheck.canonicalize(resolved)
    }
}
