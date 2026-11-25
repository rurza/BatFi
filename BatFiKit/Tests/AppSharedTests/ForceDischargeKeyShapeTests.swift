//
//  ForceDischargeKeyShapeTests.swift
//  BatFi
//
//  These cases pin the shapes "Run on Battery" gates on. The important one is that
//  CHIE is accepted as `hex_`: that is what the firmware on every current Mac
//  actually reports, while CHIE's own SMCKey declaration says `ui8 `. "Aligning"
//  the gate to the declaration would disable force discharge across the fleet, and
//  before these tests existed it would have done so with a green suite.
//
//  The mirror image is CH0I/CH0J, whose type has never been measured on hardware.
//  There the gate must stay permissive, and re-tightening it to a guessed type must
//  fail here rather than on somebody's Intel Mac.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ForceDischargeKeyShapeTests {
    private func cap(_ code: String, _ type: String, _ size: UInt32,
                     readable: Bool = true, writable: Bool = true) -> SMCKeyCapability {
        SMCKeyCapability(code: code, type: type, size: size, isReadable: readable, isWritable: writable)
    }

    // MARK: - CHIE, the measured shape

    /// The load-bearing case: CHIE as measured on a Mac15,8 / M3 Max, firmware
    /// mBoot-18000.161.9 — hex_/1, attributes 0xd4. Force discharge works on current
    /// hardware only because this is accepted.
    @Test func measuredCHIEIsUsableForReadingAndWriting() {
        let measured = cap("CHIE", "hex_", 1)
        #expect(ForceDischargeKeyShape.isUsable(measured, writable: true))
        #expect(ForceDischargeKeyShape.isUsable(measured, writable: false))
    }

    /// The encoding CHIE's SMCKey declaration implies. Never measured, but plausible
    /// on firmware nobody here has, and byte-identical at size 1 — so it is accepted
    /// alongside hex_ rather than instead of it.
    @Test func declaredCHIETypeIsAlsoUsable() {
        #expect(ForceDischargeKeyShape.isUsable(cap("CHIE", "ui8 ", 1), writable: true))
    }

    /// Accepting two encodings is not the same as accepting any. A CHIE of some third
    /// type is a differently-meaning key wearing the same name.
    @Test func rejectsCHIEOfAnUnrelatedType() {
        #expect(!ForceDischargeKeyShape.isUsable(cap("CHIE", "ui32", 1), writable: true))
        #expect(!ForceDischargeKeyShape.isUsable(cap("CHIE", "flt ", 1), writable: true))
        #expect(!ForceDischargeKeyShape.isUsable(cap("CHIE", "ui32", 1), writable: false))
    }

    /// Size is measured too, and a size mismatch means the write lands somewhere else.
    @Test func rejectsCHIEOfTheWrongSize() {
        #expect(!ForceDischargeKeyShape.isUsable(cap("CHIE", "hex_", 2), writable: true))
        #expect(!ForceDischargeKeyShape.isUsable(cap("CHIE", "hex_", 4), writable: false))
    }

    /// A read-only CHIE accepts the write and ignores it, which would report a
    /// discharge that never engaged. It may still back a status read.
    @Test func readOnlyCHIEIsReadableButNotWritable() {
        let readOnly = cap("CHIE", "hex_", 1, writable: false)
        #expect(!ForceDischargeKeyShape.isUsable(readOnly, writable: true))
        #expect(ForceDischargeKeyShape.isUsable(readOnly, writable: false))
    }

    // MARK: - CH0I / CH0J, the unmeasured legacy pair

    /// The pin for "permissive where unmeasured". CH0I/CH0J are the Intel-era
    /// mechanism and no machine here can report their type, so the gate must not
    /// demand one. Re-tightening this to the declared `ui8 ` would disable force
    /// discharge across the Intel fleet, silently — and would fail here first.
    @Test func legacyKeysAreUsableWhateverTypeTheFirmwareReports() {
        for type in ["ui8 ", "hex_", "ui32", "si8 ", "    "] {
            #expect(ForceDischargeKeyShape.isUsable(cap("CH0I", type, 1), writable: true),
                    "CH0I of type '\(type)' should be usable: its type has never been measured")
            #expect(ForceDischargeKeyShape.isUsable(cap("CH0J", type, 1), writable: true),
                    "CH0J of type '\(type)' should be usable: its type has never been measured")
        }
    }

    /// Permissive about type is not permissive about everything: size and writability
    /// are still real constraints, and dropping the type check must not drop them.
    @Test func legacyKeysStillRequireSizeAndWritability() {
        #expect(!ForceDischargeKeyShape.isUsable(cap("CH0I", "ui8 ", 2), writable: true))
        #expect(!ForceDischargeKeyShape.isUsable(cap("CH0J", "ui8 ", 4), writable: false))
        #expect(!ForceDischargeKeyShape.isUsable(cap("CH0I", "ui8 ", 1, writable: false), writable: true))
    }

    /// A read-only legacy key can still answer the status read, same as CHIE.
    @Test func readOnlyLegacyKeyStillBacksAStatusRead() {
        #expect(ForceDischargeKeyShape.isUsable(cap("CH0I", "ui8 ", 1, writable: false), writable: false))
    }

    // MARK: - Rules that hold for every force-discharge key

    /// Zero-size placeholders are reported by real firmware and can be neither read
    /// nor written. No key, measured or not, is usable at size 0.
    @Test func zeroSizePlaceholdersAreNeverUsable() {
        for code in ["CHIE", "CH0I", "CH0J"] {
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "hex_", 0), writable: true))
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "hex_", 0), writable: false))
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "ui8 ", 0), writable: false))
        }
    }

    /// A key that cannot be read cannot be verified after a write, so it is not a
    /// mechanism BatFi will drive — not even for the write-only direction.
    @Test func nonReadableKeysAreNeverUsable() {
        for code in ["CHIE", "CH0I", "CH0J"] {
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "hex_", 1, readable: false), writable: true))
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "hex_", 1, readable: false), writable: false))
        }
    }

    /// Only the three force-discharge keys drive this mechanism. Anything else of the
    /// right shape — CHTE, the bfD0 decoy, a charge-inhibit key — must be refused,
    /// otherwise a permissive type rule turns into "write whatever matched".
    @Test func unrelatedKeysAreNeverUsable() {
        for code in ["CHTE", "CH0B", "CH0C", "bfD0", "ACLC"] {
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "hex_", 1), writable: true))
            #expect(!ForceDischargeKeyShape.isUsable(cap(code, "ui8 ", 1), writable: false))
        }
    }

    /// Every key the gate accepts is one the helper actually probes. If a key is added
    /// to the shape rules without being probed, the gate silently never sees it.
    @Test func everyForceDischargeKeyIsProbed() {
        for code in ["CHIE", "CH0I", "CH0J"] {
            #expect(ChargeBackendResolver.probedKeys.contains(code))
        }
    }

    // MARK: - The "any type" affordance itself

    /// `matchesAnyType` drops only the type expectation. The rejections it keeps —
    /// zero size, wrong size, non-readable, non-writable — are the ones that describe
    /// real firmware behaviour.
    @Test func matchesAnyTypeKeepsEveryNonTypeRejection() {
        #expect(cap("CH0I", "anything", 1).matchesAnyType(size: 1, writable: true))
        #expect(!cap("CH0I", "anything", 0).matchesAnyType(size: 0, writable: false))
        #expect(!cap("CH0I", "anything", 2).matchesAnyType(size: 1, writable: false))
        #expect(!cap("CH0I", "anything", 1, readable: false).matchesAnyType(size: 1, writable: false))
        #expect(!cap("CH0I", "anything", 1, writable: false).matchesAnyType(size: 1, writable: true))
        #expect(cap("CH0I", "anything", 1, writable: false).matchesAnyType(size: 1, writable: false))
    }

    /// The typed gate must stay strictly narrower than the untyped one, so relaxing a
    /// measured key to "any type" can never happen by accident through this door.
    @Test func typedMatchIsNarrowerThanUntyped() {
        let measured = cap("CHTE", "ui32", 4)
        #expect(measured.matches(type: "ui32", size: 4, writable: true))
        #expect(!measured.matches(type: "hex_", size: 4, writable: true))
        #expect(measured.matchesAnyType(size: 4, writable: true))
    }
}
