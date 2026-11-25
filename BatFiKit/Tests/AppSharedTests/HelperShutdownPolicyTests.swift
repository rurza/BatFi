//
//  HelperShutdownPolicyTests.swift
//  BatFi
//
//  The rule that keeps a root daemon from outliving the app it serves, and — just as
//  important — keeps it from tearing down hardware state while that app is still there.
//
//  The asymmetry is the whole point, so it is what these tests are mostly about: a
//  *connection* dying proves nothing, because `XPCClient` tears connections down on purpose
//  and rebuilds them on the next call; a *process* dying is proof. Both directions have a
//  failure that reaches hardware. Exiting too late leaves a stale helper bound to the mach
//  service, which is what breaks the app after an in-place update. Exiting — or restoring —
//  too early releases a firmware charge band the live app is still asking for.
//

import Foundation
import Testing

@testable import Shared

@Suite struct HelperShutdownPolicyTests {
    private let appPID: pid_t = 501
    private let otherAppPID: pid_t = 502

    /// A policy with one connected client, as the helper sees it moments after launchd
    /// spawns it for a real app.
    private func connected(
        _ pid: pid_t,
        _ connection: UUID
    ) -> HelperShutdownPolicy {
        var policy = HelperShutdownPolicy()
        _ = policy.handle(.clientConnected(connection, pid: pid))
        return policy
    }

    // MARK: - Watching

    @Test("Accepting a connection starts watching the client process")
    func firstConnectionArmsTheProcessWatch() {
        var policy = HelperShutdownPolicy()

        let decisions = policy.handle(.clientConnected(UUID(), pid: appPID))

        #expect(decisions == [.watchProcess(appPID)])
    }

    /// One app, several connections — the app rebuilds its connection after every watchdog
    /// teardown. Arming a second source for a pid already watched would leak a dispatch
    /// source per teardown for the life of the daemon.
    @Test("A second connection from the same process does not arm a second watch")
    func secondConnectionFromSameProcessDoesNotRearm() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.clientConnected(UUID(), pid: appPID))

        #expect(decisions.isEmpty)
    }

    @Test("A connection from a different process is watched separately")
    func differentProcessArmsItsOwnWatch() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.clientConnected(UUID(), pid: otherAppPID))

        #expect(decisions == [.watchProcess(otherAppPID)])
    }

    // MARK: - Connection loss is not death

    /// The case this policy exists to get right. `XPCClient`'s watchdog invalidates a
    /// connection whenever a call goes unanswered for 15s, and the next call builds a new
    /// one. Treating that as the app being gone is what used to release the firmware charge
    /// band under an app that was still running and still asking for it.
    @Test("Losing every connection to a live process neither restores nor exits")
    func losingAllConnectionsToALiveProcessDoesNothing() {
        let connection = UUID()
        var policy = connected(appPID, connection)

        let decisions = policy.handle(.connectionInvalidated(connection))

        #expect(decisions.isEmpty)
    }

    @Test("A process reconnecting after a teardown is not watched twice")
    func reconnectAfterTeardownDoesNotRearm() {
        let first = UUID()
        var policy = connected(appPID, first)
        _ = policy.handle(.connectionInvalidated(first))

        let decisions = policy.handle(.clientConnected(UUID(), pid: appPID))

        #expect(decisions.isEmpty)
    }

    @Test("Invalidating an unknown connection is ignored")
    func unknownConnectionInvalidationIsIgnored() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.connectionInvalidated(UUID()))

        #expect(decisions.isEmpty)
    }

    // MARK: - Process death is death

    @Test("The last client process exiting restores hardware state and exits")
    func lastClientProcessExitRestoresAndExits() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.clientProcessExited(appPID))

        #expect(decisions == [.stopWatching(appPID), .restoreThenExit(.lastClientDied)])
    }

    /// The app crashed without ever invalidating anything. Connection bookkeeping must not
    /// be a precondition for noticing, because a killed process cannot tidy up after itself.
    @Test("Process exit is acted on even though the connection was never invalidated")
    func processExitDoesNotRequireAConnectionInvalidationFirst() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.clientProcessExited(appPID))

        #expect(decisions.contains(.restoreThenExit(.lastClientDied)))
    }

    @Test("A process that died after dropping its connections still triggers the exit")
    func processExitAfterConnectionLossStillExits() {
        let connection = UUID()
        var policy = connected(appPID, connection)
        _ = policy.handle(.connectionInvalidated(connection))

        let decisions = policy.handle(.clientProcessExited(appPID))

        #expect(decisions == [.stopWatching(appPID), .restoreThenExit(.lastClientDied)])
    }

    // MARK: - More than one client

    /// Two copies of BatFi can be connected at once. The helper serves both, so it belongs
    /// to neither until both are gone.
    @Test("One of two client processes exiting does not bring the helper down")
    func oneOfTwoClientsExitingKeepsTheHelperAlive() {
        var policy = connected(appPID, UUID())
        _ = policy.handle(.clientConnected(UUID(), pid: otherAppPID))

        let decisions = policy.handle(.clientProcessExited(appPID))

        #expect(decisions == [.stopWatching(appPID)])
    }

    @Test("The helper exits once the second of two client processes exits")
    func secondClientExitBringsTheHelperDown() {
        var policy = connected(appPID, UUID())
        _ = policy.handle(.clientConnected(UUID(), pid: otherAppPID))
        _ = policy.handle(.clientProcessExited(appPID))

        let decisions = policy.handle(.clientProcessExited(otherAppPID))

        #expect(decisions == [.stopWatching(otherAppPID), .restoreThenExit(.lastClientDied)])
    }

    @Test("An exit reported twice for the same process is not acted on again")
    func repeatedProcessExitIsIgnored() {
        var policy = connected(appPID, UUID())
        _ = policy.handle(.clientProcessExited(appPID))

        let decisions = policy.handle(.clientProcessExited(appPID))

        #expect(decisions.isEmpty)
    }

    // MARK: - Asked to quit

    /// `quit()` has to restore on its way out, and not because the caller might have
    /// forgotten to. `HelperConnectionManager.takeOwnership()` sends it to a *foreign*
    /// helper to evict it, and that helper may be holding a firmware charge band — enforced
    /// by the hardware, invisible in System Settings, and outliving every process that knows
    /// about it. Nothing else in that sequence can release it.
    @Test("A quit request restores hardware state before exiting")
    func quitRequestRestoresBeforeExiting() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.quitRequested)

        #expect(decisions == [.restoreThenExit(.askedToQuit)])
    }

    @Test("A quit request is honoured even with another client process still alive")
    func quitRequestIsHonouredWithASecondClientAlive() {
        var policy = connected(appPID, UUID())
        _ = policy.handle(.clientConnected(UUID(), pid: otherAppPID))

        let decisions = policy.handle(.quitRequested)

        #expect(decisions == [.restoreThenExit(.askedToQuit)])
    }

    // MARK: - Startup grace

    /// launchd can spawn the daemon for a lookup that never becomes a connection — the
    /// code-signing requirement rejects the client, or the caller gives up. Without this the
    /// helper sits as an idle root process until reboot.
    @Test("A helper nobody ever connected to exits when the startup grace expires")
    func startupGraceExitsAHelperNobodyUsed() {
        var policy = HelperShutdownPolicy()

        let decisions = policy.handle(.startupGraceExpired)

        #expect(decisions == [.exitWithoutRestoring(.neverUsed)])
    }

    /// Nothing was ever driven, so there is nothing to hand back. A restore here would be a
    /// root daemon writing hardware state on behalf of an app that never asked it to.
    @Test("The startup grace exit does not restore, having never held anything")
    func startupGraceExitDoesNotRestore() {
        var policy = HelperShutdownPolicy()

        let decisions = policy.handle(.startupGraceExpired)

        #expect(!decisions.contains(.restoreThenExit(.neverUsed)))
    }

    @Test("The startup grace is a no-op once a client has connected")
    func startupGraceIgnoredAfterAClientConnected() {
        var policy = connected(appPID, UUID())

        let decisions = policy.handle(.startupGraceExpired)

        #expect(decisions.isEmpty)
    }

    /// The grace is about whether the helper was ever *used*, not whether it is busy right
    /// now. A client that connected and then dropped its connection is still a client; its
    /// death is what brings the helper down, and the timer must not race that.
    @Test("The startup grace stays a no-op after a client connects and disconnects")
    func startupGraceIgnoredAfterAClientConnectedAndLeft() {
        let connection = UUID()
        var policy = connected(appPID, connection)
        _ = policy.handle(.connectionInvalidated(connection))

        let decisions = policy.handle(.startupGraceExpired)

        #expect(decisions.isEmpty)
    }
}
