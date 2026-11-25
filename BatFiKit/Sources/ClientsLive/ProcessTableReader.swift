//
//  ProcessTableReader.swift
//  BatFi
//
//  Reads the user's processes and their resource coalitions from the kernel, for
//  `AppThrottleClient`.
//

import AppShared
import Darwin
import Foundation
import os
import Shared

/// The process table, read on request, with each process's coalition remembered between
/// reads so that it is asked for once per process.
final class ProcessTableReader: @unchecked Sendable {
    private let logger = Logger(category: "Process Table")
    private let lock = NSLock()
    private var scanner = ProcessTableScanner()
    private var hasReportedMissingLaunchd = false

    /// The whole table — every process BatFi's user runs, and launchd — or none.
    func snapshot() -> [ProcessRecord] {
        let uid = getuid()
        let ownPID = getpid()
        return lock.withLock {
            scanner.scan(
                // launchd is root's, so the user's listing leaves it out; the policy dates
                // the boot by it.
                pids: KernelProcesses.pids(ownedBy: uid).map { $0 + [1] },
                ownPID: ownPID,
                row: { pid in
                    guard pid == 1 else { return KernelProcesses.row(of: pid) }
                    switch KernelProcesses.launchdRow() {
                    case let .success(row):
                        return row
                    case let .failure(failure):
                        reportMissingLaunchd(failure)
                        return nil
                    }
                },
                coalition: KernelProcesses.resourceCoalition(of:)
            )
        }
    }

    /// Without launchd's start time, the policy cannot tell a ledger entry left from before
    /// this boot, whose coalition is somebody else's by now. Said once, since it would be
    /// true of every scan. Called under the lock.
    private func reportMissingLaunchd(_ failure: KernelProcesses.LaunchdReadFailure) {
        guard !hasReportedMissingLaunchd else { return }
        hasReportedMissingLaunchd = true
        logger.notice("Could not read launchd's start time (\(failure.description, privacy: .public)); entries left from before this boot cannot be told apart.")
    }
}

/// The kernel calls behind the process table.
enum KernelProcesses {
    /// Every process whose effective user is `uid`, or nil where the kernel could not list
    /// them all.
    static func pids(ownedBy uid: uid_t) -> [pid_t]? {
        let stride = MemoryLayout<pid_t>.stride
        // Without a buffer, the kernel answers with room for every process on the Mac.
        let estimate = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard estimate > 0 else { return nil }
        var capacity = Int(estimate) / stride + 64
        // Processes start between the calls. A listing that fills its buffer may have been
        // cut short, so it is taken again in a bigger one.
        for _ in 0 ..< 3 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let bytes = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(UInt32(PROC_UID_ONLY), uid, buffer.baseAddress, Int32(buffer.count))
            }
            guard bytes > 0 else { return nil }
            let count = Int(bytes) / stride
            if count < capacity { return Array(pids.prefix(count)) }
            capacity *= 2
        }
        return nil
    }

    /// The process's start time, parent and owner, or nil where it has exited.
    static func row(of pid: pid_t) -> ProcessTableScanner.Row? {
        // launchd is root's, and `PROC_PIDTBSDINFO` refuses to describe another user's
        // process.
        if pid == 1 { return try? launchdRow().get() }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              // Exited, and waiting for its parent to collect it.
              info.pbi_status != UInt32(SZOMB)
        else { return nil }
        return ProcessTableScanner.Row(
            identity: ProcessIdentity(pid: pid, startSec: info.pbi_start_tvsec, startUsec: info.pbi_start_tvusec),
            ppid: Int32(bitPattern: info.pbi_ppid),
            uid: info.pbi_uid
        )
    }

    /// launchd's row, from `sysctl`, which describes any user's process. Its start time is
    /// the same clock `PROC_PIDTBSDINFO` reads.
    static func launchdRow() -> Result<ProcessTableScanner.Row, LaunchdReadFailure> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, 1]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return .failure(.sysctl(errno: errno))
        }
        // An answer of another size is not launchd's row; no errno says why.
        guard size == MemoryLayout<kinfo_proc>.stride else { return .failure(.unexpectedSize(size)) }
        let start = info.kp_proc.p_starttime
        return .success(ProcessTableScanner.Row(
            identity: ProcessIdentity(pid: 1, startSec: UInt64(start.tv_sec), startUsec: UInt64(start.tv_usec)),
            ppid: info.kp_eproc.e_ppid,
            uid: info.kp_eproc.e_ucred.cr_uid
        ))
    }

    /// Why launchd's row could not be read.
    enum LaunchdReadFailure: Error, CustomStringConvertible {
        case sysctl(errno: Int32)
        case unexpectedSize(Int)

        var description: String {
            switch self {
            case let .sysctl(errno): "sysctl failed with errno \(errno)"
            case let .unexpectedSize(size): "sysctl answered \(size) bytes, not \(MemoryLayout<kinfo_proc>.stride)"
            }
        }
    }

    /// The process's resource coalition — the one an app shares with everything it spawns,
    /// and with the XPC services launchd starts for it — or nil where it could not be read.
    static func resourceCoalition(of pid: pid_t) -> UInt64? {
        var info = ProcPIDCoalitionInfo()
        let size = Int32(MemoryLayout<ProcPIDCoalitionInfo>.size)
        guard proc_pidinfo(pid, procPIDCoalitionInfo, 0, &info, size) == size else { return nil }
        // 0 is no coalition at all.
        let resource = info.coalitionID.0
        return resource == 0 ? nil : resource
    }
}

/// `PROC_PIDCOALITIONINFO`, a `proc_pidinfo` flavour the SDK does not publish. From xnu,
/// `bsd/sys/proc_info_private.h` (the `PRIVATE` part of `bsd/sys/proc_info.h` in older
/// releases). Unlike most flavours, it answers for any process.
private let procPIDCoalitionInfo: Int32 = 20

/// `struct proc_pidcoalitioninfo` from the same header:
///
///     struct proc_pidcoalitioninfo {
///         uint64_t coalition_id[COALITION_NUM_TYPES];
///         uint64_t reserved1;
///         uint64_t reserved2;
///         uint64_t reserved3;
///     };
///
/// `COALITION_NUM_TYPES` is 2 (`osfmk/mach/coalition.h`): index 0 is
/// `COALITION_TYPE_RESOURCE`, index 1 `COALITION_TYPE_JETSAM`. 40 bytes, which is what the
/// kernel answers on macOS 27.
private struct ProcPIDCoalitionInfo {
    var coalitionID: (UInt64, UInt64) = (0, 0)
    var reserved1: UInt64 = 0
    var reserved2: UInt64 = 0
    var reserved3: UInt64 = 0
}
