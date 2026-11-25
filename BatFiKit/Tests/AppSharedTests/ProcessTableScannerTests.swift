//
//  ProcessTableScannerTests.swift
//  BatFi
//
//  Unit tests for how BatFi puts together the process table the throttle policy reads, and
//  how seldom it asks the kernel for a process's resource coalition.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ProcessTableScannerTests {
    private typealias Row = ProcessTableScanner.Row

    private let me: UInt32 = 501
    private let batFiPID: Int32 = 900

    private func id(_ pid: Int32, startedAt start: UInt64? = nil) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startSec: start ?? 1_700_000_000 + UInt64(pid), startUsec: 250)
    }

    /// What the kernel answers, and a count of the coalition reads BatFi made.
    private final class Mac {
        var pids: [Int32]?
        var rows: [Int32: Row]
        var coalitions: [Int32: UInt64]
        private(set) var coalitionReads: [Int32] = []

        init(rows: [Row], coalitions: [Int32: UInt64]) {
            pids = rows.map(\.identity.pid)
            self.rows = Dictionary(uniqueKeysWithValues: rows.map { ($0.identity.pid, $0) })
            self.coalitions = coalitions
        }

        func readCoalition(_ pid: Int32) -> UInt64? {
            coalitionReads.append(pid)
            return coalitions[pid]
        }

        func forgetReads() { coalitionReads = [] }
    }

    private func row(_ pid: Int32, parent ppid: Int32 = 1, startedAt start: UInt64? = nil) -> Row {
        Row(identity: id(pid, startedAt: start), ppid: ppid, uid: me)
    }

    /// BatFi, Slack and one of its helpers, each in its own coalition but the helper.
    private func mac() -> Mac {
        Mac(
            rows: [row(batFiPID), row(100), row(101, parent: 100)],
            coalitions: [batFiPID: 90, 100: 10, 101: 10]
        )
    }

    private func scan(_ scanner: inout ProcessTableScanner, _ mac: Mac) -> [ProcessRecord] {
        scanner.scan(
            pids: mac.pids,
            ownPID: batFiPID,
            row: { mac.rows[$0] },
            coalition: mac.readCoalition
        )
    }

    // MARK: - The table

    @Test func everyProcessIsListedWithItsParentOwnerAndCoalition() {
        var scanner = ProcessTableScanner()
        let table = scan(&scanner, mac())

        #expect(Set(table) == [
            ProcessRecord(identity: id(batFiPID), ppid: 1, uid: me, coalitionID: 90),
            ProcessRecord(identity: id(100), ppid: 1, uid: me, coalitionID: 10),
            ProcessRecord(identity: id(101), ppid: 100, uid: me, coalitionID: 10),
        ])
    }

    /// Listed, then gone before it could be read: it is not in the table, and the rest is.
    @Test func aProcessThatExitsMidScanIsLeftOut() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.rows[101] = nil

        let table = scan(&scanner, mac)

        #expect(table.map(\.identity.pid).sorted() == [100, batFiPID])
    }

    @Test func aProcessListedTwiceIsInTheTableOnce() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.pids = [batFiPID, 100, 101, 100]

        let table = scan(&scanner, mac)

        #expect(table.map(\.identity.pid).sorted() == [100, 101, batFiPID])
    }

    /// pid 0 is the kernel, and to the calls BatFi makes it means BatFi itself.
    @Test func pidsThatNameNoProcessAreLeftOut() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.pids = [0, -1] + (mac.pids ?? [])
        mac.rows[0] = row(0, parent: 0)

        let table = scan(&scanner, mac)

        #expect(table.map(\.identity.pid).sorted() == [100, 101, batFiPID])
        #expect(!mac.coalitionReads.contains(0))
    }

    // MARK: - All or nothing

    /// The policy takes a table without BatFi in it for a failed read, so a table that is
    /// not whole is not handed over at all.
    @Test func aFailedListingGivesNoTable() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.pids = nil

        #expect(scan(&scanner, mac).isEmpty)
    }

    @Test func aTableWithoutBatFiIsNoTable() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.pids = [100, 101]

        #expect(scan(&scanner, mac).isEmpty)
    }

    @Test func aTableInWhichBatFiCouldNotBeReadIsNoTable() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.rows[batFiPID] = nil

        #expect(scan(&scanner, mac).isEmpty)
    }

    // MARK: - Coalitions, read once

    @Test func aProcessCoalitionIsReadOnceForAsLongAsItRuns() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        _ = scan(&scanner, mac)
        mac.forgetReads()

        let table = scan(&scanner, mac)

        #expect(mac.coalitionReads.isEmpty)
        #expect(table.first { $0.identity.pid == 101 }?.coalitionID == 10)
    }

    @Test func onlyAProcessNotSeenBeforeHasItsCoalitionRead() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        _ = scan(&scanner, mac)
        mac.forgetReads()
        mac.pids?.append(102)
        mac.rows[102] = row(102, parent: 100)
        mac.coalitions[102] = 10

        let table = scan(&scanner, mac)

        #expect(mac.coalitionReads == [102])
        #expect(table.first { $0.identity.pid == 102 }?.coalitionID == 10)
    }

    /// A process never changes coalition. What a later read would say — failing, here —
    /// does not replace what was read.
    @Test func aKnownCoalitionIsKeptWhateverALaterReadWouldSay() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        _ = scan(&scanner, mac)
        mac.coalitions[101] = nil

        let table = scan(&scanner, mac)

        #expect(table.first { $0.identity.pid == 101 }?.coalitionID == 10)
    }

    /// A coalition that could not be read is not remembered as missing: it is asked for
    /// again on the next scan.
    @Test func aCoalitionThatCouldNotBeReadIsAskedForAgain() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        mac.coalitions[101] = nil
        let first = scan(&scanner, mac)
        mac.forgetReads()
        mac.coalitions[101] = 10

        let second = scan(&scanner, mac)

        #expect(first.first { $0.identity.pid == 101 }?.coalitionID == nil)
        #expect(mac.coalitionReads == [101])
        #expect(second.first { $0.identity.pid == 101 }?.coalitionID == 10)
    }

    // MARK: - Forgetting

    @Test func aProcessThatExitedIsForgotten() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        _ = scan(&scanner, mac)
        mac.pids = [batFiPID, 100]

        _ = scan(&scanner, mac)

        #expect(Set(scanner.knownCoalitions.keys) == [id(batFiPID), id(100)])
    }

    /// Pids are reused. A new process under an old pid is another process, and its
    /// coalition is read afresh rather than taken from the one that exited.
    @Test func aNewProcessUnderAReusedPidHasItsOwnCoalitionRead() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        _ = scan(&scanner, mac)
        mac.forgetReads()
        mac.rows[101] = row(101, parent: 1, startedAt: 1_800_000_000)
        mac.coalitions[101] = 55

        let table = scan(&scanner, mac)

        #expect(mac.coalitionReads == [101])
        #expect(table.first { $0.identity.pid == 101 } == ProcessRecord(
            identity: id(101, startedAt: 1_800_000_000),
            ppid: 1,
            uid: me,
            coalitionID: 55
        ))
        #expect(scanner.knownCoalitions[id(101)] == nil)
    }

    /// A scan that failed says nothing about which processes exited, so it does not make
    /// the next one read everything again.
    @Test func aFailedScanForgetsNothing() {
        var scanner = ProcessTableScanner()
        let mac = mac()
        _ = scan(&scanner, mac)
        let full = mac.pids
        mac.pids = [100]
        _ = scan(&scanner, mac)
        mac.pids = full
        mac.forgetReads()

        _ = scan(&scanner, mac)

        #expect(mac.coalitionReads.isEmpty)
    }
}
