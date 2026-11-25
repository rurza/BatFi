//
//  ThrottleResult.swift
//  BatFi
//
//  What the kernel said when BatFi confined a process to the efficiency cores, or gave it
//  back.
//

import Foundation

/// The outcome of `setpriority(PRIO_DARWIN_PROCESS, pid, …)`.
public enum ThrottleResult: Equatable, Sendable {
    case ok
    /// The process has exited.
    case noSuchProcess
    /// The kernel refused: another user's process (EPERM), or one a security policy
    /// protects (EPERM or EACCES). Asking again will not change that.
    case notPermitted
    /// Any other failure, with its `errno`.
    case failed(Int32)

    /// Reads a `setpriority` call from what it returned and the `errno` it left. `errno`
    /// only means something when the call failed.
    public init(returnValue: Int32, errno: Int32) {
        guard returnValue != 0 else {
            self = .ok
            return
        }
        switch errno {
        case ESRCH: self = .noSuchProcess
        case EPERM, EACCES: self = .notPermitted
        default: self = .failed(errno)
        }
    }

    /// Makes `call` — a `setpriority` — for `pid`, and reads its outcome.
    ///
    /// A pid that names no other process is never passed on: to `setpriority`, 0 is the
    /// caller itself, and demoting it would slow BatFi down.
    public static func applying(to pid: Int32, _ call: (id_t) -> Int32) -> ThrottleResult {
        guard pid > 0 else { return .failed(EINVAL) }
        let returnValue = call(id_t(pid))
        return ThrottleResult(returnValue: returnValue, errno: errno)
    }
}
