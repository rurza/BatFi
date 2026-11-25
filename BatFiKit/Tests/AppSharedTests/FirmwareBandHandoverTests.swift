//
//  FirmwareBandHandoverTests.swift
//  BatFi
//
//  Under `.firmwareRange` with sailing on, the app asks the helper for a band reaching down
//  to the resume level. The client can quietly send the one-value call instead — an older
//  helper, an unreadable version, a remembered refusal — and the firmware then keeps today's
//  band. The app measures and names only the band the firmware was actually handed.
//

import Foundation
import Testing

@testable import AppShared
import Shared

@Suite struct FirmwareBandHandoverTests {
    @Test func beforeAnyApplyNoSailingBandIsClaimed() {
        let handover = FirmwareBandHandover()
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == nil)
    }

    @Test func aRangeThatWentOutIsTheBandMeasured() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: 70, call: .range)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == 70)
    }

    /// An older helper, an unreadable version or a remembered refusal: the firmware keeps
    /// today's band, so no resume level is named.
    @Test func aRangeThatFellBackLeavesTodaysBand() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: 70, call: .limitOnly)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == nil)
    }

    @Test func withSailingOffTodaysBandIsMeasured() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: nil, call: .limitOnly)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: nil) == nil)
        // Even after a band went out: sailing turned off asks for nothing more.
        handover.record(limit: 80, resumeLevel: 70, call: .range)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: nil) == nil)
    }

    /// A call carrying no resume level is the one-value call whatever is reported.
    @Test func aCallWithoutAResumeLevelIsNeverARange() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: nil, call: .range)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == nil)
    }

    /// The band handed over is the one for those exact levels; any other request has not
    /// been handed over yet.
    @Test func aBandForOtherLevelsIsNotThisOne() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: 70, call: .range)
        #expect(handover.bandResumeLevel(limit: 85, requestedResumeLevel: 70) == nil)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 65) == nil)
    }

    /// A fallback followed by a range going out — a new helper process, or changed levels —
    /// brings the sailing band back.
    @Test func aLaterRangeBringsTheSailingBandBack() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: 70, call: .limitOnly)
        handover.record(limit: 80, resumeLevel: 70, call: .range)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == 70)
    }

    /// The last call is what the firmware holds: a band that went out and then fell back is
    /// today's band again.
    @Test func aFallbackAfterARangeLeavesTodaysBand() {
        var handover = FirmwareBandHandover()
        handover.record(limit: 80, resumeLevel: 70, call: .range)
        handover.record(limit: 80, resumeLevel: 70, call: .limitOnly)
        #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == nil)
    }

    /// An unchanged state names the same level on every pass.
    @Test func anUnchangedStateIsStableFromPassToPass() {
        var handover = FirmwareBandHandover()
        for _ in 0..<3 {
            handover.record(limit: 80, resumeLevel: 70, call: .range)
            #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == 70)
        }
        for _ in 0..<3 {
            handover.record(limit: 80, resumeLevel: 70, call: .limitOnly)
            #expect(handover.bandResumeLevel(limit: 80, requestedResumeLevel: 70) == nil)
        }
    }
}
