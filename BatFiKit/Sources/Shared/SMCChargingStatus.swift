//
//  SMCChargingStatus.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Foundation

public class SMCChargingStatus: NSObject, Codable, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding: Bool = true

    public func encode(with coder: NSCoder) {
        coder.encode(forceDischarging, forKey: "forceDischarging")
        coder.encode(inhitbitCharging, forKey: "inhitbitCharging")
        // Encoded as an object rather than with `encode(_: Bool, forKey:)` because the
        // absence of a value is itself a value here, and the primitive encoding invents
        // the *permissive* one. `decodeBool` answers a missing key with `false`, i.e.
        // `lidClosed == false`, i.e. **lid open** — and an open lid is what enables force
        // discharge (`ChargingManager` gates `turnOnDischarging` on
        // `lidOpened || disableSleepDuringDischarge`, so an open lid is sufficient on its
        // own; a closed one leaves the user's sleep setting to decide). So the
        // obvious encoding would let BatFi discharge on AC on a Mac whose lid it never
        // read. `nil` instead reaches the app as "not known" and routes it to
        // `fetchLidStatus()`, which answers "closed" and holds discharge back.
        //
        // Note that the two `false`s in this path mean opposite things: `lidClosed ==
        // false` is permissive (lid open), while `fetchLidStatus() -> false` is the
        // conservative answer (treat as closed).
        coder.encode(lidClosed.map(NSNumber.init(value:)), forKey: "lidClosed")
    }

    public required init?(coder: NSCoder) {
        forceDischarging = coder.decodeBool(forKey: "forceDischarging")
        inhitbitCharging = coder.decodeBool(forKey: "inhitbitCharging")
        lidClosed = coder.decodeObject(of: NSNumber.self, forKey: "lidClosed")?.boolValue
        super.init()
    }

    public let forceDischarging: Bool
    public let inhitbitCharging: Bool

    /// Whether the lid is shut, or `nil` when the helper could not find out.
    ///
    /// Optional because the key it comes from is not guaranteed to exist. A firmware that
    /// has dropped it must still be able to report the rest of the status — the charge
    /// state is what the app's mode is decided from, and letting one absent key throw the
    /// whole read leaves the app stuck in `ChargingMode.initial` forever.
    public let lidClosed: Bool?

    /// The same fact the app already speaks in: `AppChargingState.lidOpened` is optional
    /// too, and every consumer of it already has an answer for "not known".
    public var lidOpened: Bool? {
        lidClosed.map { !$0 }
    }

    public var isCharging: Bool {
        !forceDischarging && !inhitbitCharging
    }

    public init(
        forceDischarging: Bool,
        inhitbitCharging: Bool,
        lidClosed: Bool?
    ) {
        self.forceDischarging = forceDischarging
        self.inhitbitCharging = inhitbitCharging
        self.lidClosed = lidClosed
        super.init()
    }

    public override var description: String {
        """
        Status:
        forceDischarging: \(forceDischarging)
        inhitbitCharging: \(inhitbitCharging)
        lidClosed: \(lidClosed.map(String.init) ?? "unknown")
        """
    }
}
