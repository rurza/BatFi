//
//  AudioActivity.swift
//  BatFi
//
//  Which processes are playing or recording audio, from CoreAudio's process objects, for
//  `AppThrottleClient`.
//

import AppShared
import CoreAudio
import Foundation
import os
import Shared

/// Reads CoreAudio's process objects: one for every process connected to the audio system,
/// saying whether it is running input or output right now.
enum AudioProcesses {
    private static let logger = Logger(category: "Audio Activity")
    private static let knowledge = AudioKnowledge()
    /// The processes already said to be spared on a guess.
    private static let sparedOnAGuess = ReportedOnce<pid_t>()

    /// The processes running audio input or output now, or nil where that is not known — the
    /// caller then keeps what it knew, rather than taking everybody for silent.
    static func activePIDs() -> Set<pid_t>? {
        let activity = AudioActivityReading.activity(of: processObjects(), state: state(of:))
        // Said when it changes, not on every read: the caller may ask every few seconds.
        switch knowledge.record(isKnown: activity != nil) {
        case .becameUnknown:
            logger.notice("Could not tell which processes play or record audio; keeping what was known.")
        case .becameKnown:
            logger.notice("Can tell which processes play or record audio again.")
        case nil:
            break
        }
        // Once per process, so that "this app is never slowed" can be answered from the log.
        for pid in sparedOnAGuess.firstReports(of: activity?.unreadablePIDs ?? []).sorted() {
            logger.notice("Couldn't read the audio state of pid \(pid, privacy: .public) (\(processName(pid), privacy: .public)); leaving its app unslowed.")
        }
        return activity?.activePIDs
    }

    /// The process's name, as `ps` shows it, for the log.
    private static func processName(_ pid: pid_t) -> String {
        var name = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return "unknown" }
        return String(cString: name)
    }

    /// Every process object, or nil where the list could not be read whole.
    static func processObjects() -> [AudioObjectID]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let stride = MemoryLayout<AudioObjectID>.stride
        return AudioActivityReading.readList(
            count: {
                var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
                var size: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
                return Int(size) / stride
            },
            read: { capacity in
                var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
                var objects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: capacity)
                var size = UInt32(capacity * stride)
                guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
                return Array(objects.prefix(Int(size) / stride))
            }
        )
    }

    /// What the process object says, asking no more than it takes. One whose process has
    /// left the audio system answers `kAudioHardwareBadObjectError` (measured on macOS 27).
    private static func state(of object: AudioObjectID) -> AudioActivityReading.ProcessState {
        var pid: pid_t = 0
        let pidStatus = read(kAudioProcessPropertyPID, of: object, into: &pid)
        guard pidStatus == noErr else {
            return pidStatus == kAudioHardwareBadObjectError ? .gone : .unreadable(pid: nil)
        }
        var couldNotTell = false
        for selector in [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
            var running: UInt32 = 0
            let status = read(selector, of: object, into: &running)
            if status == kAudioHardwareBadObjectError { return .gone }
            if status != noErr {
                couldNotTell = true
            } else if running != 0 {
                return .active(pid: pid)
            }
        }
        return couldNotTell ? .unreadable(pid: pid) : .idle
    }

    static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func read<Value: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID,
        into value: inout Value
    ) -> OSStatus {
        var address = globalAddress(selector)
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    }
}

/// Whether the last read could tell who plays audio, so that only a change is logged.
/// Reads may come from any thread.
private final class AudioKnowledge: @unchecked Sendable {
    enum Change {
        case becameUnknown
        case becameKnown
    }

    private let lock = NSLock()
    private var isKnown = true

    /// The change this read makes, if any.
    func record(isKnown: Bool) -> Change? {
        lock.withLock {
            defer { self.isKnown = isKnown }
            guard isKnown != self.isKnown else { return nil }
            return isKnown ? .becameKnown : .becameUnknown
        }
    }
}

/// Calls `onChange` each time a process starts or stops running audio input or output, and
/// each time a process connects to or leaves the audio system, until stopped.
///
/// Listens to the system object's process list, and to the audio state of every process
/// object on it, following the list as it changes.
///
/// Uses CoreAudio's function-pointer listeners, not its block ones. Swift imports
/// `AudioObjectPropertyListenerBlock` as a Swift closure, so every call bridges a new block,
/// and removing a block listener never matches the one added — measured on macOS 27: the
/// removal answers `noErr` and the listener keeps firing. A function-pointer listener is
/// removed by its function and client data, which is a token looked up under a lock rather
/// than a pointer to the watcher, so a call already on its way can never reach a watcher
/// that has gone.
final class AudioActivityWatcher: @unchecked Sendable {
    private static let logger = Logger(category: "Audio Activity")
    /// Measured on macOS 27 (26A428): a process starting or stopping output announces
    /// `kAudioProcessPropertyIsRunning` (and its device lists), but not
    /// `kAudioProcessPropertyIsRunningInput` or `…Output`, whose values change silently. So
    /// `IsRunning` is what brings the news; the other two are listened to as well in case a
    /// release announces them.
    private static let processProperties = [
        kAudioProcessPropertyIsRunning,
        kAudioProcessPropertyIsRunningInput,
        kAudioProcessPropertyIsRunningOutput,
    ]
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private let onChange: @Sendable () -> Void
    /// Everything below is only touched on it.
    private let queue = DispatchQueue(label: "software.micropixels.BatFi.AudioActivity")
    private var token: Int?
    private var watchedProcesses: Set<AudioObjectID> = []

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [self] in
            guard token == nil else { return }
            let token = AudioListenerRegistry.shared.register(self)
            self.token = token
            var address = AudioProcesses.globalAddress(kAudioHardwarePropertyProcessObjectList)
            let status = AudioObjectAddPropertyListener(Self.system, &address, audioListener, Self.clientData(token))
            if status != noErr {
                Self.logger.notice("Could not listen to the audio system's process list: \(status, privacy: .public)")
            }
            follow(AudioProcesses.processObjects() ?? [])
        }
    }

    func stop() {
        queue.async { [self] in
            guard let token else { return }
            var address = AudioProcesses.globalAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListener(Self.system, &address, audioListener, Self.clientData(token))
            follow([])
            AudioListenerRegistry.shared.unregister(token)
            self.token = nil
        }
    }

    /// Called by the listener, off the queue.
    fileprivate func didChange(_ object: AudioObjectID) {
        queue.async { [self] in
            guard token != nil else { return }
            if object == Self.system {
                follow(AudioProcesses.processObjects() ?? Array(watchedProcesses))
            }
            onChange()
        }
    }

    /// Listens to exactly these process objects.
    private func follow(_ objects: [AudioObjectID]) {
        guard let token else { return }
        let clientData = Self.clientData(token)
        let current = Set(objects)
        for object in watchedProcesses.subtracting(current) {
            // The object is usually gone with its process, and the removal fails with it.
            for property in Self.processProperties {
                var address = AudioProcesses.globalAddress(property)
                AudioObjectRemovePropertyListener(object, &address, audioListener, clientData)
            }
        }
        for object in current.subtracting(watchedProcesses) {
            for property in Self.processProperties {
                var address = AudioProcesses.globalAddress(property)
                AudioObjectAddPropertyListener(object, &address, audioListener, clientData)
            }
        }
        watchedProcesses = current
    }

    private static func clientData(_ token: Int) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: token)
    }
}

/// Every property change the watchers listen to lands here, on a CoreAudio thread. Made a C
/// function pointer once, so that each removal names the very function that was added.
private let audioListener: AudioObjectPropertyListenerProc = { object, _, _, clientData in
    AudioListenerRegistry.shared.watcher(for: Int(bitPattern: clientData))?.didChange(object)
    return noErr
}

/// The running watchers, by the token their listeners carry.
private final class AudioListenerRegistry: @unchecked Sendable {
    static let shared = AudioListenerRegistry()

    private struct Entry {
        weak var watcher: AudioActivityWatcher?
    }

    private let lock = NSLock()
    private var lastToken = 0
    private var entries: [Int: Entry] = [:]

    func register(_ watcher: AudioActivityWatcher) -> Int {
        lock.withLock {
            lastToken += 1
            entries[lastToken] = Entry(watcher: watcher)
            return lastToken
        }
    }

    func unregister(_ token: Int) {
        lock.withLock { _ = entries.removeValue(forKey: token) }
    }

    func watcher(for token: Int) -> AudioActivityWatcher? {
        lock.withLock { entries[token]?.watcher }
    }
}
