//
//  AudioActivityReadingTests.swift
//  BatFi
//
//  Unit tests for how BatFi decides which processes are playing or recording audio, and
//  when it cannot tell.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct AudioActivityReadingTests {
    private typealias Reading = AudioActivityReading

    /// A list the audio system reports, which may change between being measured and read.
    private final class AudioSystem {
        /// What each measurement answers, in turn; nil is a failed measurement.
        var measurements: [Int?]
        /// The whole list at each read, in turn; nil is a failed read.
        var lists: [[UInt32]?]
        private(set) var measured = 0
        private(set) var reads: [Int] = []

        init(measurements: [Int?], lists: [[UInt32]?]) {
            self.measurements = measurements
            self.lists = lists
        }

        func measure() -> Int? {
            defer { measured += 1 }
            return measured < measurements.count ? measurements[measured] : measurements.last ?? nil
        }

        /// Answers as much of the list as fits.
        func read(capacity: Int) -> [UInt32]? {
            defer { reads.append(capacity) }
            let index = reads.count
            guard let list = index < lists.count ? lists[index] : lists.last ?? nil else { return nil }
            return Array(list.prefix(capacity))
        }
    }

    private func objects(_ count: Int) -> [UInt32] { (0 ..< UInt32(count)).map { 100 + $0 } }

    private func readList(_ system: AudioSystem) -> [UInt32]? {
        Reading.readList(count: system.measure, read: system.read(capacity:))
    }

    // MARK: - Reading the process list whole

    @Test func aListThatFitsIsReadOnce() {
        let system = AudioSystem(measurements: [5], lists: [objects(5)])

        #expect(readList(system) == objects(5))
        #expect(system.reads.count == 1)
    }

    @Test func anEmptyListIsAnswered() {
        let system = AudioSystem(measurements: [0], lists: [[]])

        #expect(readList(system) == [])
    }

    /// Processes connected between the measurement and the read filled the room left for
    /// them, so the list may have been cut short: it is measured and read again.
    @Test func aListThatGrewPastItsRoomIsReadAgain() {
        let grown = objects(5 + Reading.slack + 3)
        let system = AudioSystem(measurements: [5, grown.count], lists: [grown, grown])

        #expect(readList(system) == grown)
        #expect(system.reads.count == 2)
    }

    @Test func aFailedMeasurementIsTriedAgain() {
        let system = AudioSystem(measurements: [nil, 5], lists: [objects(5)])

        #expect(readList(system) == objects(5))
    }

    @Test func aFailedReadIsTriedAgain() {
        let system = AudioSystem(measurements: [5], lists: [nil, objects(5)])

        #expect(readList(system) == objects(5))
        #expect(system.reads.count == 2)
    }

    /// Not an empty list: nobody would be taken to be playing audio.
    @Test func aListThatCannotBeReadIsUnknownAfterAFewTries() {
        let system = AudioSystem(measurements: [5], lists: [nil])

        #expect(readList(system) == nil)
        #expect(system.reads.count == Reading.attempts)
    }

    @Test func aListThatKeepsGrowingIsUnknownAfterAFewTries() {
        let system = AudioSystem(measurements: [5], lists: [objects(100)])

        #expect(readList(system) == nil)
        #expect(system.reads.count == Reading.attempts)
    }

    // MARK: - Who is playing or recording

    private func activePIDs(
        _ processes: [UInt32]?,
        _ states: [UInt32: Reading.ProcessState]
    ) -> Set<Int32>? {
        Reading.activePIDs(of: processes, state: { states[$0] ?? .gone })
    }

    @Test func processesRunningInputOrOutputAreActive() {
        let pids = activePIDs([1, 2, 3], [1: .active(pid: 501), 2: .idle, 3: .active(pid: 502)])

        #expect(pids == [501, 502])
    }

    @Test func nobodyPlayingIsAnEmptySetNotAnUnknownOne() {
        #expect(activePIDs([1, 2], [1: .idle, 2: .idle]) == [])
    }

    @Test func aListThatCouldNotBeReadLeavesActivityUnknown() {
        #expect(activePIDs(nil, [:]) == nil)
    }

    /// Its process left the audio system between the list and the read: it plays nothing.
    @Test func aProcessThatLeftIsSkipped() {
        #expect(activePIDs([1, 2], [1: .gone, 2: .active(pid: 501)]) == [501])
    }

    /// A process that is still there, but cannot say whether it is playing, might be: it is
    /// taken for playing, which spares only that app. The rest of the answer stands, so one
    /// such process cannot leave the whole answer unknown for as long as it runs.
    @Test func aProcessThatCannotSayWhetherItPlaysIsTakenForPlaying() {
        let pids = activePIDs(
            [1, 2, 3, 4],
            [1: .unreadable(pid: 501), 2: .active(pid: 502), 3: .idle, 4: .gone]
        )

        #expect(pids == [501, 502])
    }

    /// Without its pid there is no telling which app to spare, so the answer is not known,
    /// rather than silence.
    @Test func aProcessThatCannotSayWhoItIsLeavesActivityUnknown() {
        #expect(activePIDs([1, 2], [1: .unreadable(pid: nil), 2: .active(pid: 501)]) == nil)
    }

    @Test func anUnreadableProcessObjectWithoutAProcessNamesNoPid() {
        #expect(activePIDs([1, 2], [1: .unreadable(pid: 0), 2: .active(pid: 501)]) == [501])
    }

    @Test func aProcessObjectWithoutAProcessNamesNoPid() {
        #expect(activePIDs([1, 2, 3], [1: .active(pid: 0), 2: .active(pid: -1), 3: .active(pid: 501)]) == [501])
    }

    // MARK: - Which apps are spared on a guess

    private func activity(
        _ processes: [UInt32]?,
        _ states: [UInt32: Reading.ProcessState]
    ) -> Reading.Activity? {
        Reading.activity(of: processes, state: { states[$0] ?? .gone })
    }

    /// Those taken for playing only because they could not say are told apart, so that the
    /// log can say which app is left unslowed on a guess.
    @Test func processesThatCouldNotSayAreToldApart() {
        let found = activity(
            [1, 2, 3, 4],
            [1: .unreadable(pid: 501), 2: .active(pid: 502), 3: .idle, 4: .unreadable(pid: 0)]
        )

        #expect(found == Reading.Activity(activePIDs: [501, 502], unreadablePIDs: [501]))
    }

    /// One of its objects says it plays: it is spared for playing, not on a guess.
    @Test func aProcessThatSaysItPlaysOnAnotherObjectIsNotAGuess() {
        let found = activity([1, 2], [1: .unreadable(pid: 501), 2: .active(pid: 501)])

        #expect(found == Reading.Activity(activePIDs: [501], unreadablePIDs: []))
    }

    @Test func anUnknownReadingSparesNobodyOnAGuess() {
        #expect(activity(nil, [:]) == nil)
        #expect(activity([1, 2], [1: .unreadable(pid: 501), 2: .unreadable(pid: nil)]) == nil)
    }

    @Test func theActivePIDsAreTheActivitysOwn() {
        let states: [UInt32: Reading.ProcessState] = [1: .unreadable(pid: 501), 2: .active(pid: 502), 3: .idle]
        #expect(activePIDs([1, 2, 3], states) == activity([1, 2, 3], states)?.activePIDs)
    }
}

@Suite struct ReportedOnceTests {
    @Test func eachKeyIsReportedTheFirstTimeOnly() {
        let reported = ReportedOnce<Int32>()

        #expect(reported.firstReports(of: [501, 502]) == [501, 502])
        #expect(reported.firstReports(of: [501, 503]) == [503])
        #expect(reported.firstReports(of: [501, 502, 503]) == [])
        #expect(reported.firstReports(of: []) == [])
    }

    /// Audio is read from more than one task at a time; however many see the same pid at
    /// once, it is reported once.
    @Test func concurrentReadersReportAKeyOnce() async {
        let reported = ReportedOnce<Int32>()

        let counts = await withTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 64 {
                group.addTask { reported.firstReports(of: [501]).count }
            }
            return await group.reduce(0, +)
        }

        #expect(counts == 1)
    }
}
