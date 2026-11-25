//
//  SystemFirmwareTests.swift
//  BatFi
//
//  The firmware token is an opaque cache key and diagnostic string. Only its
//  extraction from a fixed-size NUL-padded IORegistry buffer is testable.
//

import Foundation
import Testing

@testable import Shared

@Suite struct SystemFirmwareTests {
    @Test func parsesNULPaddedBuffer() {
        var bytes = Array("mBoot-18000.161.9".utf8)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 239))
        #expect(SystemFirmware.parse(Data(bytes)) == "mBoot-18000.161.9")
    }

    @Test func parsesUnpaddedBuffer() {
        #expect(SystemFirmware.parse(Data("mBoot-18000.161.9".utf8)) == "mBoot-18000.161.9")
    }

    /// The prefix changed from iBoot- to mBoot- in macOS 26.4, which is exactly why
    /// the token is never parsed for meaning — both must come back verbatim.
    @Test func returnsPrefixVerbatim() {
        #expect(SystemFirmware.parse(Data("iBoot-11881.81.4".utf8)) == "iBoot-11881.81.4")
    }

    @Test func rejectsEmptyAndAllNUL() {
        #expect(SystemFirmware.parse(Data()) == nil)
        #expect(SystemFirmware.parse(Data([UInt8](repeating: 0, count: 256))) == nil)
    }
}
