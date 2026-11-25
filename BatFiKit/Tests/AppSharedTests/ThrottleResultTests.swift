//
//  ThrottleResultTests.swift
//  BatFi
//
//  Unit tests for how BatFi reads the kernel's answer when it demotes a process to the
//  efficiency cores or gives it back.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ThrottleResultTests {
    /// Stands in for `setpriority`: fails with `code`, or succeeds when there is none.
    private func call(failingWith code: Int32?) -> (id_t) -> Int32 {
        { _ in
            guard let code else { return 0 }
            errno = code
            return -1
        }
    }

    @Test func aCallThatSucceedsIsOK() {
        #expect(ThrottleResult.applying(to: 4242, call(failingWith: nil)) == .ok)
    }

    /// The process exited between the scan and the call.
    @Test func aProcessThatIsGoneIsReportedAsGone() {
        #expect(ThrottleResult.applying(to: 4242, call(failingWith: ESRCH)) == .noSuchProcess)
    }

    /// Another user's process, or one a security policy protects: asking again will not help.
    @Test func aRefusalIsReportedAsNotPermitted() {
        #expect(ThrottleResult.applying(to: 4242, call(failingWith: EPERM)) == .notPermitted)
    }

    /// A security policy may refuse with EACCES rather than EPERM. It is a refusal all the
    /// same, and asking again on every rescan would not change it.
    @Test func aRefusalByASecurityPolicyIsReportedAsNotPermitted() {
        #expect(ThrottleResult.applying(to: 4242, call(failingWith: EACCES)) == .notPermitted)
    }

    @Test(arguments: [EINVAL, ENOMEM, EIO])
    func anyOtherFailureCarriesItsErrno(code: Int32) {
        #expect(ThrottleResult.applying(to: 4242, call(failingWith: code)) == .failed(code))
    }

    /// The call is made with the pid it was given.
    @Test func theCallIsMadeForThatProcess() {
        var asked: [id_t] = []
        _ = ThrottleResult.applying(to: 4242) { pid in
            asked.append(pid)
            return 0
        }
        #expect(asked == [4242])
    }

    /// To `setpriority`, pid 0 is the caller itself: demoting it would slow BatFi down. A
    /// negative pid names no process at all.
    @Test(arguments: [Int32(0), -1, -4242])
    func aPidThatNamesNoOtherProcessIsNeverPassedOn(pid: Int32) {
        var called = false
        let result = ThrottleResult.applying(to: pid) { _ in
            called = true
            return 0
        }
        #expect(!called)
        #expect(result == .failed(EINVAL))
    }

    /// `errno` is only set by a failure, so one left over from an earlier call means nothing
    /// once the call succeeds.
    @Test func aStaleErrnoDoesNotTurnSuccessIntoFailure() {
        errno = EPERM
        #expect(ThrottleResult.applying(to: 4242) { _ in 0 } == .ok)
    }
}
