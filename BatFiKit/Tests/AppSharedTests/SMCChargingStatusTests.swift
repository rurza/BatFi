//
//  SMCChargingStatusTests.swift
//  BatFi
//
//  The lid is the one field in the status that the helper may fail to read: its SMC key
//  is not guaranteed to exist on every firmware, and a firmware that dropped it used to
//  take the whole status read down — leaving the app pinned to `ChargingMode.initial`.
//
//  What is pinned here is the part that can be: that "unknown" is representable at all,
//  and that it survives the trip through NSSecureCoding to the app. The obvious encoding
//  is the broken one, and broken in the dangerous direction — `decodeBool` answers a
//  missing key with `false`, i.e. `lidClosed == false`, i.e. **lid open**, which is the
//  state that *enables* force discharge. It would let BatFi discharge on AC on a Mac
//  whose lid it never read. Unknown must stay unknown so the app can answer "closed".
//

import Foundation
import Testing

@testable import Shared

@Suite("SMC charging status")
struct SMCChargingStatusTests {
    private func roundTrip(_ status: SMCChargingStatus) throws -> SMCChargingStatus {
        let data = try NSKeyedArchiver.archivedData(withRootObject: status, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: SMCChargingStatus.self, from: data)
        return try #require(decoded)
    }

    @Test("An unreadable lid is unknown, not closed")
    func unknownLidIsNotClosed() {
        let status = SMCChargingStatus(forceDischarging: false, inhitbitCharging: false, lidClosed: nil)
        #expect(status.lidClosed == nil)
        #expect(status.lidOpened == nil)
    }

    @Test("A read lid is reported as opened or closed")
    func knownLid() {
        #expect(SMCChargingStatus(forceDischarging: false, inhitbitCharging: false, lidClosed: true).lidOpened == false)
        #expect(SMCChargingStatus(forceDischarging: false, inhitbitCharging: false, lidClosed: false).lidOpened == true)
    }

    @Test("Unknown survives the trip to the app", arguments: [true, false, nil] as [Bool?])
    func lidSurvivesSecureCoding(lidClosed: Bool?) throws {
        let decoded = try roundTrip(
            SMCChargingStatus(forceDischarging: true, inhitbitCharging: true, lidClosed: lidClosed)
        )
        #expect(decoded.lidClosed == lidClosed)
        #expect(decoded.forceDischarging)
        #expect(decoded.inhitbitCharging)
    }

    @Test("An unknown lid does not describe itself as a state the helper never read")
    func descriptionSaysUnknown() {
        let status = SMCChargingStatus(forceDischarging: false, inhitbitCharging: false, lidClosed: nil)
        #expect(status.description.contains("lidClosed: unknown"))
    }
}
