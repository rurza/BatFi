//
//  OtherChargeToolWarning.swift
//  BatFi
//
//  What BatFi tells the user about another charge-control tool installed on this Mac: in
//  Charging settings, one warning per tool saying what it fights over and how to remove it;
//  in the menu, one row while any is installed.
//
//  The sentence for what a tool fights over follows `OtherChargeTool.contention(backend:)`,
//  so the battery CLI on macOS 27-era firmware is never said to touch the charge limit —
//  it can't there — but is said to override the MagSafe light and end Run on Battery.
//

import Foundation
import L10n
import Shared

public struct OtherChargeToolWarning: Identifiable, Hashable, Sendable {
    public let id: OtherChargeTool
    /// What the tool fights BatFi over. The first line of the warning.
    public let problem: String
    /// How to remove it, every matched footprint included. The second line: one sentence
    /// per step. Terminal commands are wrapped in backticks, so the view can render it as
    /// Markdown and show them as code.
    public let removal: String

    public init(detected: DetectedChargeTool, backend: ChargeBackend?) {
        let strings = L10n.OtherChargeTools.self
        let name = detected.tool.displayName
        id = detected.tool
        switch detected.tool.contention(backend: backend) {
        case .chargeLimit:
            problem = strings.chargeLimitProblem(name)
        case .magSafeLightAndForceDischarge:
            problem = strings.magSafeLightAndDischargeProblem(name)
        }
        // Backticks, so the view can render the commands as code.
        removal = Self.removal(for: detected, markingCommand: { "`\($0)`" })
    }

    /// How to remove `detected`, every matched footprint included, one sentence per step,
    /// with each Terminal command passed through `markingCommand` — backticks where the
    /// text is rendered as Markdown, quotation marks where it is not.
    public static func removal(for detected: DetectedChargeTool, markingCommand: (String) -> String) -> String {
        let name = detected.tool.displayName
        return detected.removal.enumerated()
            .map { index, step in sentence(for: step, toolName: name, isFirst: index == 0, markingCommand: markingCommand) }
            .joined(separator: " ")
    }

    /// One removal step as a sentence: the first starts "To remove <tool>, …", the rest
    /// "Then …". In-app steps always come first (see `OtherChargeToolRemovalStep`), so
    /// they have no "Then" form.
    private static func sentence(
        for step: OtherChargeToolRemovalStep,
        toolName name: String,
        isFirst: Bool,
        markingCommand: (String) -> String
    ) -> String {
        let strings = L10n.OtherChargeTools.self
        switch step {
        case let .terminalCommands(commands):
            let marked = commands.map(markingCommand)
            if marked.count == 1 {
                return isFirst ? strings.removeWithCommand(name, command: marked[0]) : strings.thenRunCommand(marked[0])
            }
            let list = ListFormatter.localizedString(byJoining: marked)
            return isFirst ? strings.removeWithCommands(name, commands: list) : strings.thenRunCommands(list)
        case let .moveToTrash(apps):
            let list = ListFormatter.localizedString(byJoining: apps)
            return isFirst ? strings.removeByMovingToTrash(name, apps: list) : strings.thenMoveToTrash(list)
        case .inAppAlDente:
            return strings.removeAlDente(name)
        case .inAppBatteryToolkit:
            return strings.removeBatteryToolkit(name)
        case let .battAppUninstallDaemon(appName):
            return strings.removeBattApp(name, app: appName)
        }
    }

    /// The menu row's title, or nil when there is nothing to warn about. One tool is named;
    /// several are not, which keeps the row short and spares translators a plural.
    public static func menuTitle(for detected: [DetectedChargeTool]) -> String? {
        switch detected.count {
        case 0: nil
        case 1: L10n.OtherChargeTools.menuOneTool(detected[0].tool.displayName)
        default: L10n.OtherChargeTools.menuSeveralTools
        }
    }

    /// The grey line under the menu row, saying where the removal steps are.
    public static func menuDetail(for detected: [DetectedChargeTool]) -> String? {
        switch detected.count {
        case 0: nil
        case 1: L10n.OtherChargeTools.menuDetailOneTool
        default: L10n.OtherChargeTools.menuDetailSeveralTools
        }
    }
}
