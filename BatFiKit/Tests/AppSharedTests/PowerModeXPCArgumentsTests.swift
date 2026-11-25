//
//  PowerModeXPCArgumentsTests.swift
//  BatFi
//
//  Unit tests for what the battery-only Low Power Mode XPC calls accept and how their
//  values cross the connection. The helper runs pmset as root with these, so anything it
//  was not built to write has to be refused here, before pmset ever sees it.
//

import Foundation
import Testing

@testable import Shared

@Suite struct PowerModeXPCArgumentsTests {
    private typealias Arguments = PowerModeXPCArguments

    private let armedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - pmset write arguments

    @Test(arguments: [UInt8(0), 1, 2])
    func writesEveryPowermodeSetting(_ value: UInt8) {
        #expect(
            Arguments.pmsetBatteryWrite(value, usesPowermodeKey: true)
                == ["-b", "powermode", "\(value)"]
        )
    }

    @Test(arguments: [UInt8(0), 1])
    func writesEveryLowpowermodeSetting(_ value: UInt8) {
        #expect(
            Arguments.pmsetBatteryWrite(value, usesPowermodeKey: false)
                == ["-b", "lowpowermode", "\(value)"]
        )
    }

    @Test(arguments: [UInt8(3), 4, 127, 255])
    func refusesAPowermodeValueItCannotHold(_ value: UInt8) {
        #expect(Arguments.pmsetBatteryWrite(value, usesPowermodeKey: true) == nil)
    }

    /// `lowpowermode` has no High Power: 2 is only a setting under `powermode`.
    @Test(arguments: [UInt8(2), 3, 255])
    func refusesALowpowermodeValueItCannotHold(_ value: UInt8) {
        #expect(Arguments.pmsetBatteryWrite(value, usesPowermodeKey: false) == nil)
    }

    // MARK: - Arming the restore on exit

    @Test(arguments: [UInt8(0), 2])
    func armsARestoreOfAutomaticOrHighPower(_ previous: UInt8) {
        let record = Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: previous),
            written: 1,
            acAtWrite: NSNumber(value: UInt8(0)),
            usesPowermodeKey: true,
            armedAt: armedAt
        )
        #expect(record == AutoLowPowerModeRecord(
            usesPowermodeKey: true,
            previousBatteryValue: previous,
            writtenBatteryValue: 1,
            acValueAtWrite: 0,
            engagedAt: armedAt
        ))
    }

    @Test func armsWithoutAnACValueWhereTheMacPublishesNone() {
        let record = Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: UInt8(0)),
            written: 1,
            acAtWrite: nil,
            usesPowermodeKey: false,
            armedAt: armedAt
        )
        #expect(record?.acValueAtWrite == nil)
        #expect(record?.usesPowermodeKey == false)
        #expect(record?.previousBatteryValue == 0)
    }

    /// Restoring 1 would put Low Power Mode *on* at exit — BatFi never takes a Low Power
    /// Mode that was already on, so no record it made can ask for that.
    @Test func refusesToRestoreLowPower() {
        #expect(Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: UInt8(1)),
            written: 1,
            acAtWrite: 0,
            usesPowermodeKey: true,
            armedAt: armedAt
        ) == nil)
    }

    @Test func refusesToRestoreHighPowerUnderLowpowermode() {
        #expect(Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: UInt8(2)),
            written: 1,
            acAtWrite: 0,
            usesPowermodeKey: false,
            armedAt: armedAt
        ) == nil)
    }

    @Test(arguments: [UInt8(0), 2, 3])
    func refusesAWrittenValueOtherThanLowPower(_ written: UInt8) {
        #expect(Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: UInt8(0)),
            written: written,
            acAtWrite: 0,
            usesPowermodeKey: true,
            armedAt: armedAt
        ) == nil)
    }

    /// 256 would wrap to 0 through `uint8Value` and arm a restore nobody asked for.
    @Test(arguments: [NSNumber(value: 256), NSNumber(value: -1), NSNumber(value: 1.5)])
    func refusesARestoreValueThatIsNotAByte(_ restoreValue: NSNumber) {
        #expect(Arguments.exitRestoreRecord(
            restoreValue: restoreValue,
            written: 1,
            acAtWrite: 0,
            usesPowermodeKey: true,
            armedAt: armedAt
        ) == nil)
    }

    @Test(arguments: [NSNumber(value: 256), NSNumber(value: -1), NSNumber(value: 0.5)])
    func refusesAnACValueThatIsNotAByte(_ acAtWrite: NSNumber) {
        #expect(Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: UInt8(0)),
            written: 1,
            acAtWrite: acAtWrite,
            usesPowermodeKey: true,
            armedAt: armedAt
        ) == nil)
    }

    /// The helper asks the policy's own question of the record it rebuilt, so the two ends
    /// cannot disagree about what "still BatFi's" means.
    @Test func theArmedRecordIsStillOwnedExactlyWhereTheAppsIs() {
        let record = Arguments.exitRestoreRecord(
            restoreValue: NSNumber(value: UInt8(2)),
            written: 1,
            acAtWrite: NSNumber(value: UInt8(0)),
            usesPowermodeKey: true,
            armedAt: armedAt
        )!
        let untouched = PowerModeBySource(battery: 1, ac: 0, usesPowermodeKey: true)
        let userChoseAlways = PowerModeBySource(battery: 1, ac: 1, usesPowermodeKey: true)
        let userTurnedItOff = PowerModeBySource(battery: 0, ac: 0, usesPowermodeKey: true)
        #expect(AutoLowPowerModePolicy.isStillOwned(record, live: untouched))
        #expect(!AutoLowPowerModePolicy.isStillOwned(record, live: userChoseAlways))
        #expect(!AutoLowPowerModePolicy.isStillOwned(record, live: userTurnedItOff))
    }

    // MARK: - Reading the reply

    @Test func readsBothProfilesFromTheReply() {
        #expect(
            Arguments.powerModeBySource(
                battery: NSNumber(value: UInt8(1)),
                ac: NSNumber(value: UInt8(0)),
                usesPowermodeKey: true
            ) == PowerModeBySource(battery: 1, ac: 0, usesPowermodeKey: true)
        )
    }

    /// The helper answers with no values at all only when pmset could not be read, or
    /// published neither key — "unknown", never "both profiles absent".
    @Test func anEmptyReplyIsUnknown() {
        #expect(Arguments.powerModeBySource(battery: nil, ac: nil, usesPowermodeKey: false) == nil)
        #expect(Arguments.powerModeBySource(battery: nil, ac: nil, usesPowermodeKey: true) == nil)
    }

    @Test func keepsTheProfileThatWasThereWhenTheOtherIsMissing() {
        #expect(
            Arguments.powerModeBySource(battery: NSNumber(value: UInt8(0)), ac: nil, usesPowermodeKey: false)
                == PowerModeBySource(battery: 0, ac: nil, usesPowermodeKey: false)
        )
    }

    /// A battery value that is not a byte is not guessed at: without it the policy does
    /// nothing, which is the safe answer.
    @Test func dropsAValueThatIsNotAByte() {
        #expect(
            Arguments.powerModeBySource(
                battery: NSNumber(value: 257),
                ac: NSNumber(value: UInt8(0)),
                usesPowermodeKey: true
            ) == PowerModeBySource(battery: nil, ac: 0, usesPowermodeKey: true)
        )
    }

    // MARK: - Bytes

    @Test func aByteIsAWholeNumberFrom0Through255() {
        #expect(Arguments.byte(NSNumber(value: UInt8(0))) == 0)
        #expect(Arguments.byte(NSNumber(value: UInt8(255))) == 255)
        #expect(Arguments.byte(NSNumber(value: 2)) == 2)
        #expect(Arguments.byte(NSNumber(value: 256)) == nil)
        #expect(Arguments.byte(NSNumber(value: -1)) == nil)
        #expect(Arguments.byte(NSNumber(value: 1.5)) == nil)
        #expect(Arguments.byte(NSNumber(value: Double.nan)) == nil)
    }
}
