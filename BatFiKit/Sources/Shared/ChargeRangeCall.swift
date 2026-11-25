//
//  ChargeRangeCall.swift
//
//
//  Whether the running helper may be asked for a charge range — a limit and a resume
//  level — or only for the one-value limit every helper has served.
//
//  Decided before asking, not by asking and seeing what happens, because of what an older
//  helper does with a message it does not know: it drops it. No error comes back. The
//  answer is the client's watchdog tearing the shared connection down a full charge-limit
//  budget later, failing every other call in flight with it — and leaving the limit
//  unapplied for that whole minute. The older helper's version, read from its code
//  signature, costs nothing and works against every helper BatFi has shipped.
//
//  In `Shared` so the comparison is reachable from the test target.
//

import Foundation

public enum ChargeRangeCall {
    /// The first helper version that serves `applyChargeRange`. Helper versions are
    /// bumped only when the helper changes, so this names the release that added the call.
    public static let minimumHelperVersion = [4, 2, 0]

    /// Whether a helper reporting `version` (its `CFBundleShortVersionString`) knows
    /// `applyChargeRange`.
    ///
    /// Anything that is not a plain dotted number is "no": the one-value call is what every
    /// helper serves, and the worst it does under sailing is put today's narrower band in
    /// force. Asking a helper that does not know the call is what stalls.
    public static func helperServesChargeRange(version: String?) -> Bool {
        guard let version, !version.isEmpty else { return false }
        var components: [Int] = []
        for part in version.split(separator: ".", omittingEmptySubsequences: false) {
            guard let number = Int(part), number >= 0 else { return false }
            components.append(number)
        }
        let width = max(components.count, minimumHelperVersion.count)
        let padded = components + Array(repeating: 0, count: width - components.count)
        let minimum = minimumHelperVersion + Array(repeating: 0, count: width - minimumHelperVersion.count)
        return !padded.lexicographicallyPrecedes(minimum)
    }
}

/// What a charge range request did: the limit actually in force, as `applyChargeLimit`
/// returns it, and which call actually went out. The client can send the one-value call in
/// the range's place, and the firmware then keeps today's band, so the app must not measure
/// or name the band it asked for (`FirmwareBandHandover`).
public struct AppliedChargeRange: Equatable, Sendable {
    public let limit: Int
    public let call: ChargeRangeCallPolicy.Call

    public init(limit: Int, call: ChargeRangeCallPolicy.Call) {
        self.limit = limit
        self.call = call
    }
}

/// Which call carries a charge range right now, from what the client has learned about the
/// running helper.
///
/// Two things are remembered, both per helper process:
/// - Its version, read once. An unreadable version is remembered too: it is the one-value
///   call either way, and reading it again would repeat a code-signature check on every
///   pass. A new helper process is a new pid, so an updated helper is read afresh.
/// - A refusal. When a helper that has the range call answers it with a failure, the
///   one-value call runs once in its place, and the range call is not asked again for that
///   process and that exact range. Without this, a range the firmware keeps rejecting turns
///   every charging pass into two engage sequences. Any change — another process, another
///   limit, another resume level — asks again.
///
/// A call the helper never answered — a dropped connection, or the watchdog's teardown —
/// is not a refusal. Nothing is known about the call, and the error goes up the way the
/// one-value call's errors always have, rather than spending a second budget on a fallback.
public struct ChargeRangeCallPolicy: Sendable {
    public enum Call: Equatable, Sendable {
        /// `applyChargeRange` — the limit with its resume level.
        case range
        /// `applyChargeLimit` — the limit alone, which every helper serves.
        case limitOnly
    }

    /// How a range call failed, told apart by which way the failure arrived.
    public enum Failure: Equatable, Sendable {
        /// The helper answered, and its answer was a failure.
        case helperRefused
        /// No answer: the connection dropped or was torn down by the watchdog.
        case noAnswer
    }

    private struct Request: Equatable, Sendable {
        let pid: pid_t
        let limit: Int
        let resumeLevel: Int
    }

    private var version: (pid: pid_t, serves: Bool)?
    private var refusal: Request?

    public init() {}

    /// Whether this process's version still has to be read.
    public func needsVersion(of pid: pid_t) -> Bool {
        version?.pid != pid
    }

    public mutating func recordVersion(_ version: String?, of pid: pid_t) {
        self.version = (pid, ChargeRangeCall.helperServesChargeRange(version: version))
    }

    /// The call to make for this request. A remembered refusal for any other request is
    /// forgotten here: the range it covered has changed, so the range call is tried again.
    public mutating func call(pid: pid_t?, limit: Int, resumeLevel: Int) -> Call {
        guard let pid, let version, version.pid == pid, version.serves else { return .limitOnly }
        let request = Request(pid: pid, limit: limit, resumeLevel: resumeLevel)
        if refusal == request { return .limitOnly }
        refusal = nil
        return .range
    }

    /// The call `call(pid:limit:resumeLevel:)` would make for this request, asked ahead and
    /// changing nothing: a remembered refusal for another request is not forgotten. Sailing
    /// under `.firmwareRange` asks it before deciding whether BatFi can enforce the hold, which
    /// needs the band's lower bound to reach the firmware.
    public func wouldCall(pid: pid_t?, limit: Int, resumeLevel: Int) -> Call {
        guard let pid, let version, version.pid == pid, version.serves else { return .limitOnly }
        return refusal == Request(pid: pid, limit: limit, resumeLevel: resumeLevel) ? .limitOnly : .range
    }

    /// Whether the one-value call should follow a failed range call. A refusal is recorded
    /// for this request; an unanswered call records nothing.
    public mutating func shouldFallBack(after failure: Failure, pid: pid_t, limit: Int, resumeLevel: Int) -> Bool {
        switch failure {
        case .helperRefused:
            refusal = Request(pid: pid, limit: limit, resumeLevel: resumeLevel)
            return true
        case .noAnswer:
            return false
        }
    }
}
