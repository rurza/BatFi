//
//  Subprocess.swift
//  BatFi
//

import Darwin
import Foundation

/// Runs a child process and collects its standard output.
///
/// This exists instead of `Process` because `Process` cannot be failed safely. Its `run()`
/// is `throws`, which reads as if `do { try process.run() } catch { … }` covers a failed
/// launch — it does not. When the underlying `posix_spawn` fails,
/// `-[NSConcreteTask launchWithDictionary:error:]` *raises* an ObjC
/// `NSInternalInconsistencyException` ("Couldn't posix_spawn: error 35"), and an ObjC
/// exception does not unwind into a Swift `catch`. It reaches the top of the thread and
/// kills the process. Under memory or process-table pressure — precisely when a menu-bar
/// utility should degrade quietly — that made a missing battery-health reading fatal.
///
/// Calling `posix_spawn` directly turns every one of those failures back into a return
/// code. Nothing here can raise: no `Process`, and no `FileHandle` (whose read methods
/// raise on I/O errors too), just file descriptors.
public enum Subprocess {
    /// The child's standard output decoded as UTF-8, or `nil` if anything at all went
    /// wrong — spawn refused, timeout elapsed, non-zero exit, killed by a signal, or output
    /// that was not UTF-8. Callers get one "no reading" answer to handle rather than six.
    ///
    /// Standard error is routed to `/dev/null`; it is never mixed into the result.
    public static func standardOutput(
        of executable: String,
        arguments: [String] = [],
        timeout: Duration
    ) async -> String? {
        guard let child = spawn(executable: executable, arguments: arguments) else { return nil }
        let (data, status) = await collect(readFD: child.readFD, pid: child.pid, timeout: timeout)
        guard status == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs `executable` for its effect, reporting only whether it succeeded. Same
    /// guarantees as `standardOutput(of:arguments:timeout:)`: a child that cannot be
    /// spawned is `false`, never a raised exception.
    @discardableResult
    public static func run(
        _ executable: String,
        arguments: [String] = [],
        timeout: Duration
    ) async -> Bool {
        await standardOutput(of: executable, arguments: arguments, timeout: timeout) != nil
    }

    /// How long a child gets to die politely before it is killed outright.
    private static let terminationGraceMS: Int32 = 2000

    private struct Child {
        let pid: pid_t
        let readFD: Int32
    }

    private static func spawn(executable: String, arguments: [String]) -> Child? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        let readFD = fds[0]
        let writeFD = fds[1]

        // Every descriptor this process holds is inherited by default, so a *concurrent*
        // spawn elsewhere would hand this pipe's write end to an unrelated child and the
        // drain below would not see EOF until that stranger exited. Two independent guards,
        // because each covers what the other cannot: `FD_CLOEXEC` protects this pipe from
        // spawns we do not control (Sparkle, Sentry), and `POSIX_SPAWN_CLOEXEC_DEFAULT`
        // protects other people's descriptors from us, including the ones opened in the
        // window between `pipe()` and these two `fcntl` calls.
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writeFD, F_SETFD, FD_CLOEXEC)

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            close(readFD)
            close(writeFD)
            return nil
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            close(readFD)
            close(writeFD)
            return nil
        }
        defer { posix_spawnattr_destroy(&attributes) }

        // A disposition of SIG_IGN survives exec, and a blocked signal stays blocked, so a
        // child inherits whatever the host has done to its signal state — and this host
        // installs handlers (Sentry's crash reporter, Sparkle). Without resetting, the
        // SIGTERM the timeout depends on can land on a child that is ignoring it, which is
        // measurable: the timeout test needed the full SIGKILL grace until this was set.
        var defaultedSignals = sigset_t()
        sigfillset(&defaultedSignals)
        posix_spawnattr_setsigdefault(&attributes, &defaultedSignals)

        var unblockedSignals = sigset_t()
        sigemptyset(&unblockedSignals)
        posix_spawnattr_setsigmask(&attributes, &unblockedSignals)

        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )

        // With CLOEXEC_DEFAULT the child starts with *only* what these actions install, so
        // stdin has to be named explicitly — a closed fd 0 makes some tools misbehave.
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fileActions, writeFD, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &fileActions, &attributes, argv, environ)
        close(writeFD)
        guard result == 0 else {
            close(readFD)
            return nil
        }
        return Child(pid: pid, readFD: readFD)
    }

    /// Drains the pipe and reaps the child on a thread that is allowed to block.
    ///
    /// Order matters. A child writing more than the pipe buffer (~64KB) sleeps until the
    /// buffer is drained, so reaping before reading deadlocks — parent waits for exit,
    /// child waits for space.
    private static func collect(readFD: Int32, pid: pid_t, timeout: Duration) async -> (Data, Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = drain(readFD, pid: pid, timeout: timeout)
                close(readFD)
                continuation.resume(returning: (data, reap(pid)))
            }
        }
    }

    /// Reads to EOF, enforcing the deadline itself rather than racing a separate timer.
    ///
    /// An earlier version put the deadline in a `Task` that signalled the child while this
    /// loop blocked in `read`. That is the wrong shape twice over: the timeout then depends
    /// on the cooperative pool having a free thread at the exact moment the app is starved
    /// enough to need a timeout, and nothing bounds the read if that task never runs.
    /// `poll` gives the wait a deadline directly, so the escalation is ordinary control flow.
    private static func drain(_ fd: Int32, pid: pid_t, timeout: Duration) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(max(0, timeout.milliseconds)) &* 1_000_000
        var terminated = false

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if !terminated, now >= deadline {
                kill(pid, SIGTERM)
                terminated = true
            }
            // Keep draining after SIGTERM: the child's stdout closes as it dies, so EOF is
            // what confirms it actually went. The grace bounds a child that ignores SIGTERM.
            let waitMS = terminated
                ? terminationGraceMS
                : Int32(min((deadline &- now) / 1_000_000, UInt64(Int32.max)))

            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, waitMS)
            if ready < 0 {
                if errno == EINTR { continue }
                return data
            }
            if ready == 0 {
                // Grace expired with the child still holding the pipe: stop asking.
                if terminated {
                    kill(pid, SIGKILL)
                    return data
                }
                continue
            }

            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                data.append(contentsOf: buffer[0 ..< count])
            } else if count == 0 {
                return data
            } else if errno != EINTR {
                return data
            }
        }
    }

    /// The child's exit code, or `-1` if it was killed by a signal or could not be reaped.
    /// A signalled child is a failure here: it is how the timeout above ends things.
    private static func reap(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            if errno != EINTR { return -1 }
        }
        // `WIFEXITED`/`WEXITSTATUS` are C macros, so they are not visible to Swift.
        guard status & 0o177 == 0 else { return -1 }
        return (status >> 8) & 0xFF
    }
}

private extension Duration {
    /// `poll` wants whole milliseconds; `components.attoseconds` is 1e-18 s.
    var milliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}
