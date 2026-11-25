//
//  ChargeLimitNotHoldingWarning.swift
//  BatFi
//
//  The notification raised once per run of the charge limit not holding, after re-applying
//  it for ten minutes has not fixed it (`ChargeHoldDriftMonitor.Response.warnTheUser`).
//
//  Another charge-limiting app is the likeliest cause BatFi can name, so when the last scan
//  found one that can write the limit on this Mac the warning names it and says how to
//  remove it. Without one, the generic warning stands as it was.
//

import Foundation
import L10n
import Shared

public struct ChargeLimitNotHoldingWarning: Equatable, Sendable {
    public let title: String
    public let body: String
    /// The tool the warning names, or nil for the generic warning.
    public let suspect: DetectedChargeTool?

    /// - Parameters:
    ///   - limit: The user's limit, already formatted ("80%").
    ///   - detected: What the last scan for other charge-control tools found.
    ///   - backend: This Mac's charge backend, or nil when it is not known yet.
    ///   - markingCommand: How a Terminal command is set off in the removal sentence. A
    ///     notification is plain text, so not backticks.
    public init(
        limit: String,
        detected: [DetectedChargeTool],
        backend: ChargeBackend?,
        markingCommand: (String) -> String
    ) {
        title = L10n.Notifications.Notification.Title.chargeLimitNotHolding
        let suspect = Self.suspect(in: detected, backend: backend)
        self.suspect = suspect
        if let suspect {
            body = L10n.OtherChargeTools.notificationChargeLimitNotHolding(
                limit: limit,
                toolName: suspect.tool.displayName,
                removal: OtherChargeToolWarning.removal(for: suspect, markingCommand: markingCommand)
            )
        } else {
            body = L10n.Notifications.Notification.Body.chargeLimitNotHolding(limit)
        }
    }

    /// The first detected tool that can write the charge limit on this Mac. The battery CLI
    /// on macOS 27-era firmware can't (`OtherChargeTool.contention(backend:)`), so it is never
    /// blamed for a limit that will not hold.
    public static func suspect(in detected: [DetectedChargeTool], backend: ChargeBackend?) -> DetectedChargeTool? {
        detected.first { $0.tool.contention(backend: backend) == .chargeLimit }
    }

    /// Wraps a command in the current locale's quotation marks.
    public static func quotingCommand(_ command: String, locale: Locale = .current) -> String {
        "\(locale.quotationBeginDelimiter ?? "“")\(command)\(locale.quotationEndDelimiter ?? "”")"
    }
}
