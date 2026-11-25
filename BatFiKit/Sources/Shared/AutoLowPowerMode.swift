//
//  AutoLowPowerMode.swift
//  BatFi
//
//  Turns Low Power Mode on for the battery profile once the charge drops to a threshold,
//  and gives back exactly what it took. Pure: no pmset, no defaults, no clock of its own,
//  so the rule that matters — BatFi only ever reverts what BatFi set — is provable in a
//  unit test rather than owed as a hardware check.
//
//  Low Power Mode is a user setting with four System Settings choices, and each is a pair
//  of per-source values: Never (battery 0, AC 0), Always (1, 1), Only on Battery (1, 0),
//  Only on Power Adapter (0, 1). BatFi writes only the battery half, and only to 1. What
//  it found there before — 0 automatic, or 2 High Power — is what it puts back.
//
//  The app decides; the helper holds a copy of the record in memory so that it can put the
//  value back when it exits, and asks `isStillOwned` the same question before it does.
//

import Foundation

/// The Low Power Mode setting of each power-source profile, as `pmset -g custom` reports it.
public struct PowerModeBySource: Equatable, Sendable {
    /// `nil` where the profile's section, or the key within it, is absent.
    public var battery: UInt8?
    public var ac: UInt8?
    /// Whether the values were read from `powermode` (0/1/2, Macs with High Power Mode)
    /// rather than `lowpowermode` (0/1).
    public var usesPowermodeKey: Bool

    public init(battery: UInt8?, ac: UInt8?, usesPowermodeKey: Bool) {
        self.battery = battery
        self.ac = ac
        self.usesPowermodeKey = usesPowermodeKey
    }

    /// The `pmset` setting name the values belong to, and so the one to write them back to.
    public static func pmsetKey(usesPowermodeKey: Bool) -> String {
        usesPowermodeKey ? "powermode" : "lowpowermode"
    }
}

/// What BatFi changed when it turned Low Power Mode on for the battery, and so what it may
/// give back.
///
/// Persisted before the write, because the setting outlives the process: a BatFi that
/// crashed while holding Low Power Mode would otherwise leave it on for good, with nothing
/// that knows it was never the user's choice.
public struct AutoLowPowerModeRecord: Codable, Equatable, Sendable {
    public var usesPowermodeKey: Bool
    /// The battery value found before the write, and the one a restore writes back. Only
    /// ever a value that can be written back — 0, or 2 under `powermode` — and never 1:
    /// BatFi does not take over a Low Power Mode that was already on.
    public var previousBatteryValue: UInt8
    /// The battery value BatFi wrote. Always `AutoLowPowerModePolicy.lowPowerValue`.
    public var writtenBatteryValue: UInt8
    /// The AC value at the time of the write — the other half of the System Settings
    /// choice — or `nil` where the Mac publishes no AC profile.
    public var acValueAtWrite: UInt8?
    public var engagedAt: Date

    public init(
        usesPowermodeKey: Bool,
        previousBatteryValue: UInt8,
        writtenBatteryValue: UInt8 = AutoLowPowerModePolicy.lowPowerValue,
        acValueAtWrite: UInt8?,
        engagedAt: Date
    ) {
        self.usesPowermodeKey = usesPowermodeKey
        self.previousBatteryValue = previousBatteryValue
        self.writtenBatteryValue = writtenBatteryValue
        self.acValueAtWrite = acValueAtWrite
        self.engagedAt = engagedAt
    }
}

public enum AutoLowPowerModePolicy {
    /// Low power, under both `powermode` and `lowpowermode`.
    public static let lowPowerValue: UInt8 = 1
    /// How far above the threshold the charge has to be before a lowered threshold gives
    /// Low Power Mode back. Without it, lowering the threshold to just under the current
    /// charge would restore now and re-engage a few percent later.
    public static let hysteresis = 5

    public struct Input: Equatable, Sendable {
        /// The user's switch. The policy reads it only through `mayHold` and `mayEngage`,
        /// which fold the licence into it.
        public var enabled: Bool
        /// Without a valid licence the feature is off, as though the switch were: nothing is
        /// turned on, and a licence known not to be valid gives back what BatFi holds by the
        /// same path. One not read yet — at launch — keeps what BatFi holds under the usual
        /// rules, so that it is not given back and taken again once the licence reads valid.
        public var license: LicenseStatus
        public var threshold: Int
        /// As `ChargerConnection.isOnBattery` answers it, so BatFi's own force discharge
        /// counts as being on the charger.
        public var onBattery: Bool
        /// 0 where the level has not been read.
        public var batteryLevel: Int
        /// `nil` where the helper could not be asked.
        public var live: PowerModeBySource?
        public var record: AutoLowPowerModeRecord?
        public var yieldedUntilCharge: Bool
        /// Stamped into a new record; the policy keeps no clock of its own.
        public var now: Date

        public init(
            enabled: Bool,
            license: LicenseStatus,
            threshold: Int,
            onBattery: Bool,
            batteryLevel: Int,
            live: PowerModeBySource?,
            record: AutoLowPowerModeRecord?,
            yieldedUntilCharge: Bool,
            now: Date
        ) {
            self.enabled = enabled
            self.license = license
            self.threshold = threshold
            self.onBattery = onBattery
            self.batteryLevel = batteryLevel
            self.live = live
            self.record = record
            self.yieldedUntilCharge = yieldedUntilCharge
            self.now = now
        }

        /// Whether BatFi may keep Low Power Mode it turned on: the switch is on, and the
        /// licence is not known to be invalid.
        public var mayHold: Bool { enabled && license.allowsHolding }

        /// Whether BatFi may turn Low Power Mode on: the switch is on, and the licence is
        /// valid.
        public var mayEngage: Bool { enabled && license.allowsTakingOn }
    }

    public enum RecordUpdate: Equatable, Sendable {
        case keep
        case set(AutoLowPowerModeRecord)
        case clear
    }

    /// Why a decision was made, for the log.
    public enum Reason: String, Equatable, Sendable {
        case liveStateUnknown
        case handedBackToUser
        /// The switch is off, or the licence is known not to be valid.
        case restoredBecauseDisabled
        case restoredOnCharger
        case restoredAboveThreshold
        case holding
        /// The setting is back to what BatFi found: the helper gave it back as it exited,
        /// or an engage write never landed. Named for the first, which is the usual one.
        case alreadyRestoredByHelper
        case notOnBattery
        /// The switch is off, or the licence is not valid or not read yet.
        case disabled
        case yieldedUntilCharge
        case levelUnknown
        case aboveThreshold
        case alreadyLowPower
        case previousValueNotRestorable
        case engaged
    }

    public struct Decision: Equatable, Sendable {
        /// The battery-profile value to write, under the record's key; `nil` writes nothing.
        public var write: UInt8?
        public var record: RecordUpdate
        /// Whether BatFi stays out until the Mac has next been on the charger, because the
        /// user took Low Power Mode over.
        public var yieldedUntilCharge: Bool
        public var reason: Reason

        public init(write: UInt8?, record: RecordUpdate, yieldedUntilCharge: Bool, reason: Reason) {
            self.write = write
            self.record = record
            self.yieldedUntilCharge = yieldedUntilCharge
            self.reason = reason
        }
    }

    /// Whether the live setting is still the one BatFi left: same key, the battery value it
    /// wrote, and the AC value it saw. Anything else means the user has chosen since — in
    /// System Settings, or with BatFi's own manual toggle — and the setting is theirs.
    public static func isStillOwned(_ record: AutoLowPowerModeRecord, live: PowerModeBySource) -> Bool {
        live.matches(record, battery: record.writtenBatteryValue)
    }

    /// Whether the live setting is exactly what BatFi found before it wrote: same key, the
    /// previous battery value, and the AC value it saw. Either the value was given back — by
    /// the helper on its way out — or BatFi's write never landed; there is nothing to give
    /// back either way.
    public static func showsPreviousValue(_ record: AutoLowPowerModeRecord, live: PowerModeBySource) -> Bool {
        live.matches(record, battery: record.previousBatteryValue)
    }

    public static func decide(_ input: Input) -> Decision {
        // Being on the charger is what ends a hand-back, whatever else is known.
        let yielded = input.onBattery && input.yieldedUntilCharge

        func decision(
            write: UInt8? = nil,
            record: RecordUpdate = .keep,
            latch: Bool? = nil,
            _ reason: Reason
        ) -> Decision {
            Decision(write: write, record: record, yieldedUntilCharge: latch ?? yielded, reason: reason)
        }

        // Never act blind: without the live value a write could overwrite whatever the user
        // just chose. A held record waits for the next reading.
        guard let live = input.live, let liveBattery = live.battery else {
            return decision(.liveStateUnknown)
        }

        if let record = input.record {
            guard isStillOwned(record, live: live) else {
                return decision(record: .clear, latch: input.onBattery, .handedBackToUser)
            }
            if !input.mayHold {
                return decision(write: record.previousBatteryValue, record: .clear, .restoredBecauseDisabled)
            }
            if !input.onBattery {
                return decision(write: record.previousBatteryValue, record: .clear, .restoredOnCharger)
            }
            if input.batteryLevel >= input.threshold + hysteresis {
                return decision(write: record.previousBatteryValue, record: .clear, .restoredAboveThreshold)
            }
            return decision(.holding)
        }

        if !input.onBattery { return decision(.notOnBattery) }
        if !input.mayEngage { return decision(.disabled) }
        if yielded { return decision(.yieldedUntilCharge) }
        if input.batteryLevel <= 0 { return decision(.levelUnknown) }
        if input.batteryLevel > input.threshold { return decision(.aboveThreshold) }
        // Already on — the user's own choice. Taking it over would mean switching it off
        // for them at the next charge.
        if liveBattery == lowPowerValue { return decision(.alreadyLowPower) }
        // A value BatFi could not write back is one it must not take: Low Power Mode would
        // stay on with no way to return what was there.
        guard canRestore(liveBattery, usesPowermodeKey: live.usesPowermodeKey) else {
            return decision(.previousValueNotRestorable)
        }

        let record = AutoLowPowerModeRecord(
            usesPowermodeKey: live.usesPowermodeKey,
            previousBatteryValue: liveBattery,
            acValueAtWrite: live.ac,
            engagedAt: input.now
        )
        return decision(write: lowPowerValue, record: .set(record), .engaged)
    }

    /// `decide`, for the first evaluation after launch.
    ///
    /// A record that survived a crash may already have been honoured: the helper exits when
    /// the app's process does, and restores the previous value on its way out. Where the
    /// live setting is exactly what the record says it was before BatFi wrote — same key,
    /// same AC value — the record is stale rather than a sign that the user took over, so it
    /// is cleared without the hand-back latch.
    public static func reconcileAtLaunch(_ input: Input) -> Decision {
        if let record = input.record,
           let live = input.live,
           showsPreviousValue(record, live: live)
        {
            return Decision(
                write: nil,
                record: .clear,
                yieldedUntilCharge: input.onBattery && input.yieldedUntilCharge,
                reason: .alreadyRestoredByHelper
            )
        }
        return decide(input)
    }

    /// The battery values a restore can write back: automatic or High Power under
    /// `powermode`, automatic under `lowpowermode`, which has no High Power.
    public static func canRestore(_ value: UInt8, usesPowermodeKey: Bool) -> Bool {
        usesPowermodeKey ? value == 0 || value == 2 : value == 0
    }

    /// Every battery value BatFi ever writes: low power, and whatever a restore can put back.
    /// The helper refuses anything else before it reaches `pmset`.
    public static func canWrite(_ value: UInt8, usesPowermodeKey: Bool) -> Bool {
        value == lowPowerValue || canRestore(value, usesPowermodeKey: usesPowermodeKey)
    }
}

private extension PowerModeBySource {
    /// Whether this is the record's key, shows `battery` for the battery profile, and still
    /// has the AC value the record saw (where it saw one).
    func matches(_ record: AutoLowPowerModeRecord, battery: UInt8) -> Bool {
        usesPowermodeKey == record.usesPowermodeKey
            && self.battery == battery
            && (record.acValueAtWrite == nil || ac == record.acValueAtWrite)
    }
}
