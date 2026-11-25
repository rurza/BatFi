//
//  SlowDownMenuButton.swift
//  BatFi
//
//  Which button, if any, a row of the menu's high-energy list offers when pointed at.
//

import Foundation

/// The button over a row of the menu's high-energy list.
public enum SlowDownMenuButton: Hashable, Sendable {
    /// Puts the app in the list of apps slowed down on battery.
    case slowDown
    /// Takes the app out of that list.
    case stopSlowing

    /// The button a row offers, or nil where it offers none.
    ///
    /// A button shows only where pressing it changes something right now. On the charger
    /// nothing is slowed, so no row offers one; nor does any without an active licence, as
    /// BatFi then slows nothing down and an app put in the list would wait for a licence. On
    /// battery, an app outside the list is offered to be slowed down, and an app in the list
    /// is offered to stop only while BatFi is slowing it down: "Stop slowing" for an app left
    /// alone — in front, playing audio, in the wait after unplugging — would say it is being
    /// slowed when it is not, and the button would hide the grey tortoise whose tooltip says
    /// why it is not. Where the throttle manager has not said yet, whether the Mac is on
    /// battery, whether the licence is active, or whether the app is slowed, the row offers
    /// nothing, as the tortoise's grey already says "not slowed". A licence not read yet
    /// counts as not said.
    ///
    /// - Parameters:
    ///   - isEnabled: The master switch.
    ///   - canSlowDown: Whether the app is one BatFi can slow down at all.
    ///   - onBattery: `SlowDownReport.onBattery`; nil before the throttle manager has said.
    ///   - licence: `SlowDownReport.licence`; nil before the throttle manager has said.
    ///   - isListed: Whether the app is in the list of apps slowed down on battery.
    ///   - status: Whether BatFi is slowing the app down right now; nil before the throttle
    ///     manager has said.
    public static func offered(
        isEnabled: Bool,
        canSlowDown: Bool,
        onBattery: Bool?,
        licence: SlowDownStatus.Licence?,
        isListed: Bool,
        status: SlowDownStatus?
    ) -> SlowDownMenuButton? {
        guard isEnabled, canSlowDown, onBattery == true, licence == .valid else { return nil }
        guard isListed else { return .slowDown }
        return status == .slowed ? .stopSlowing : nil
    }
}
