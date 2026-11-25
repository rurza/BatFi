//
//  SlowDownStatus.swift
//  BatFi
//
//  Whether BatFi is slowing each app in the list down right now, and if not, why — what the
//  menu's tortoise and its tooltip show.
//

import Foundation

/// One app in the list of apps slowed down on battery, as the menu shows it.
public enum SlowDownStatus: Hashable, Sendable {
    /// Some process of the app is on the efficiency cores now.
    case slowed
    /// Nothing of the app is, for the reason given; nil where no reason the menu could give
    /// is known to be true.
    case notSlowed(Reason?)

    /// Why an app in the list is not slowed down right now, in the order the menu prefers
    /// them where several apply: what holds for every app first, then what the user is doing
    /// with this one, then what the kernel said.
    public enum Reason: Hashable, Sendable, CaseIterable {
        /// BatFi's licence is not active. Read, and not valid — a licence not read yet gives
        /// no reason.
        case licence
        /// The Mac is on its charger, BatFi's own force discharge included.
        case charger
        /// The Mac has been on its battery for less than `OnBatterySettle.duration`.
        case justUnplugged
        /// No instance of the app is running.
        case notRunning
        /// "Background only", and the app is in front, its coalition is, or it left the front
        /// less than `FrontmostGrace.duration` ago.
        case inUse
        /// Something in the app's coalition plays or records audio.
        case audio
        /// The high-energy list has just asked it to quit; see `QuitExemptions`.
        case quitting
        /// The kernel refused to slow some of its processes down, so BatFi leaves them alone.
        case refused
    }

    /// The licence, as far as the reasons are concerned.
    public enum Licence: Hashable, Sendable {
        case valid
        case invalid
        /// Not read yet in this run.
        case unknown
    }

    /// What a pass knows once it is done.
    public struct Input: Sendable {
        public var slowedApps: [String: SlowDownMode]
        /// The master switch.
        public var isEnabled: Bool
        public var licence: Licence
        /// As `ChargerConnection.isOnBattery` answers it.
        public var onBattery: Bool
        /// `OnBatterySettle.isSettled`.
        public var batteryIsSettled: Bool
        /// The running apps, or nil where the pass did not read them.
        public var runningApps: [RunningAppRecord]?
        /// What the pass planned from, or nil where it planned nothing: it found no slowed app
        /// running, or nothing could be slowed. Only an `isActive` input tells anything about
        /// the apps; an inactive one — audio not known yet — says nothing.
        public var planned: BackgroundThrottlePolicy.Input?
        /// The processes the kernel has refused, this pass included.
        public var refused: Set<ProcessIdentity>
        /// The ledger as the pass left it.
        public var ledger: [ThrottleLedgerEntry]

        public init(
            slowedApps: [String: SlowDownMode],
            isEnabled: Bool,
            licence: Licence,
            onBattery: Bool,
            batteryIsSettled: Bool,
            runningApps: [RunningAppRecord]?,
            planned: BackgroundThrottlePolicy.Input?,
            refused: Set<ProcessIdentity>,
            ledger: [ThrottleLedgerEntry]
        ) {
            self.slowedApps = slowedApps
            self.isEnabled = isEnabled
            self.licence = licence
            self.onBattery = onBattery
            self.batteryIsSettled = batteryIsSettled
            self.runningApps = runningApps
            self.planned = planned
            self.refused = refused
            self.ledger = ledger
        }
    }

    /// The status of every app in the list.
    ///
    /// An app is slowed while the ledger holds any of its processes — the same test the
    /// tortoise's colour always made, so what the menu says follows what BatFi holds, also on
    /// the charger while a give-back the kernel failed waits for a retry. Otherwise the
    /// reason asks the policy's own questions, so it cannot tell a story the plan did not.
    public static func statuses(_ input: Input) -> [String: SlowDownStatus] {
        let held = Set(input.ledger.map(\.bundleID))
        let shared = sharedReason(input)
        var statuses: [String: SlowDownStatus] = [:]
        for (bundleID, mode) in input.slowedApps {
            if held.contains(bundleID) {
                statuses[bundleID] = .slowed
            } else if let shared {
                statuses[bundleID] = .notSlowed(shared)
            } else {
                statuses[bundleID] = .notSlowed(reason(for: bundleID, mode: mode, input))
            }
        }
        return statuses
    }

    /// The reason for every app, where nothing at all may be slowed — itself nil where none
    /// can be given. Nil where apps may be slowed.
    private static func sharedReason(_ input: Input) -> Reason?? {
        // The menu offers no button then, so there is nothing to explain.
        guard input.isEnabled else { return .some(nil) }
        if input.licence == .invalid { return .licence }
        if !input.onBattery { return .charger }
        if !input.batteryIsSettled { return .justUnplugged }
        // "Not active" would be untrue; it is read at once, so this does not last.
        if input.licence == .unknown { return .some(nil) }
        return nil
    }

    private static func reason(for bundleID: String, mode: SlowDownMode, _ input: Input) -> Reason? {
        guard let runningApps = input.planned?.runningApps ?? input.runningApps else { return nil }
        let instances = runningApps.filter { $0.bundleID == bundleID }
        let eligible = instances.filter(\.isEligible)
        // Running, but not as an app BatFi slows: "isn't running" would be untrue.
        guard !eligible.isEmpty else { return instances.isEmpty ? .notRunning : nil }
        guard let planned = input.planned, planned.isActive else { return nil }

        let table = ProcessTable(planned.processes)
        let quittingPIDs = BackgroundThrottlePolicy.quittingPIDs(planned)
        var reasons = Set<Reason>()
        for app in eligible {
            guard let reach = BackgroundThrottlePolicy.reach(of: app, input: planned, table: table) else { continue }
            let sparing = BackgroundThrottlePolicy.sparing(
                app,
                mode: mode,
                reach: reach,
                input: planned,
                quittingPIDs: quittingPIDs
            )
            for spared in sparing {
                switch spared {
                case .inUse: reasons.insert(.inUse)
                case .audio: reasons.insert(.audio)
                case .quitting: reasons.insert(.quitting)
                // Sharing BatFi's own coalition: nothing the menu could say helps.
                case .batFi: break
                }
            }
            if sparing.isEmpty, reach.targets.contains(where: { input.refused.contains($0.identity) }) {
                reasons.insert(.refused)
            }
        }
        return Reason.allCases.first(where: reasons.contains)
    }
}

/// What the throttle manager tells the menu after each pass.
public struct SlowDownReport: Hashable, Sendable {
    /// Whether the Mac is on its battery, as the pass asked `ChargerConnection.isOnBattery`
    /// — BatFi's own force discharge counts as the charger. The menu offers a slow-down
    /// button only on battery, where pressing it changes something at once. Taken from the
    /// pass rather than read by the menu itself, so that the button and the statuses beside
    /// it never answer the question differently.
    public var onBattery: Bool
    /// The licence, as the pass took it. The menu offers a slow-down button only while it is
    /// valid, since without one BatFi slows nothing down. Taken from the pass for the same
    /// reason as `onBattery`: so that the button and the tortoise's "not active" never
    /// disagree.
    public var licence: SlowDownStatus.Licence
    /// Every app in the list of apps slowed down on battery: see `SlowDownStatus`.
    public var statuses: [String: SlowDownStatus]

    public init(onBattery: Bool, licence: SlowDownStatus.Licence, statuses: [String: SlowDownStatus]) {
        self.onBattery = onBattery
        self.licence = licence
        self.statuses = statuses
    }
}
