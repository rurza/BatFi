//
//  ChargeToFullHold.swift
//
//
//  Whether BatFi is still keeping a battery at 100% because the user asked it to get there.
//
//  Customer log 2026-09-22: "Charge to 100%" armed with the charger in, a 70% limit on the
//  firmware-range backend, "Discharge battery when overcharged" on. The battery reached
//  100%, `ChargeToFullCompletion` retired the override — and the very next status pass read
//  100% against a 70–75% band with discharging allowed and force-discharged the 30% the user
//  had just asked for, for twenty minutes. Granting a request and then immediately undoing
//  it is worse than refusing it.
//
//  The hold is expressed as **the requested limit staying at 100**, not as suppressing the
//  discharge. Suppressing the discharge would be right on a mechanism BatFi can pause on
//  demand and wrong on the two it cannot: under `.firmwareRange` an inhibit writes nothing
//  below the band, so the battery would coast down from 100 with nothing topping it up, and
//  under `.systemChargeLimit` macOS drains to the limit itself and only a limit of 100 holds.
//  With 100 in force the existing no-override branch already does the right thing on its own
//  — inhibit at 100%, charge at 99% — and every rule keyed on "battery above the limit"
//  (`systemChargeAboveLimit`, `ChargeHoldDrift`) sees the same shape the armed override
//  produced, because it is the same request.
//
//  Split out of `ChargingManager` for the reason `ChargeToFullCompletion` and
//  `TempOverrideDisconnectPolicy` were: `AppCore` has no test target, and this is the third
//  rule about the life of a request the user made by hand.
//

import Foundation

public enum ChargeToFullHold {
    /// The things that can start or end a hold.
    ///
    /// Only four, and a charger *connect* is deliberately not among them: the hold was
    /// already cleared when the charger came out, so plugging back in has nothing to undo.
    public enum Event: Equatable, Sendable {
        /// `ChargeToFullCompletion.isReached` fired — the override has been retired, and
        /// this is what takes its place.
        case chargeToFullCompleted
        /// A real connected→disconnected edge. The resolved `ChargerConnection.isConnected`,
        /// not the raw reading: a derived "Battery Power" during a BatFi discharge is not an
        /// unplug — and no discharge runs while the hold is on anyway.
        case chargerDisconnected
        /// A new temp override replaced the intent this hold came from. The hold is the
        /// residue of a superseded request and must not re-assert itself once the new
        /// override ends.
        case overrideArmed
        /// Charge management turned off, or any other disengage. BatFi has no limit in force
        /// to be holding.
        case chargingHandedBack
    }

    /// The hold after `event`, given whether one is in force now.
    public static func next(holding: Bool, event: Event) -> Bool {
        switch event {
        case .chargeToFullCompleted:
            return true
        case .chargerDisconnected, .overrideArmed, .chargingHandedBack:
            return false
        }
    }

    /// The limit to request while holding: 100; otherwise the caller's own.
    ///
    /// Above the automation limit and the user's configured one, exactly as the override it
    /// came from was — the hold is the continuation of that request, not a new opinion about
    /// what the limit should be.
    public static func requestedLimit(holding: Bool, otherwise limit: Int) -> Int {
        holding ? 100 : limit
    }
}
