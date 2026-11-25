//
//  HighEnergyUsageView.swift
//
//
//  Created by Adam on 24/10/2023.
//

import AppKit
import AppShared
import L10n
import SharedUI
import SwiftUI

public struct HighEnergyUsageView: View {
    @StateObject private var model = HighEnergyUsageViewModel()

    public init() {}

    public var body: some View {
        let l10n = L10n.Menu.HighEnergyUsage.self
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.header)
                .foregroundColor(.secondary)
                .font(.callout)
                .multilineTextAlignment(.leading)
            Group {
                if let info = model.topCoalitionInfo {
                    if info.topCoalitions.count > 0 {
                        VStack {
                            ForEach(info.topCoalitions, id: \.bundleIdentifier) { coalition in
                                let bundleID = coalition.bundleIdentifier
                                let isListed = model.slowedApps[bundleID] != nil
                                let status = model.slowDownReport?.statuses[bundleID]
                                BatteryTopCoalitionInfoItem(
                                    coalition: coalition,
                                    showsTortoise: model.slowDownEnabled && coalition.canSlowDown && isListed,
                                    status: status,
                                    button: SlowDownMenuButton.offered(
                                        isEnabled: model.slowDownEnabled,
                                        canSlowDown: coalition.canSlowDown,
                                        onBattery: model.slowDownReport?.onBattery,
                                        licence: model.slowDownReport?.licence,
                                        isListed: isListed,
                                        status: status
                                    ),
                                    toggleSlowDown: { model.toggleSlowDown(bundleID) }
                                )
                            }
                        }
                    } else {
                        GroupBox {
                            Text(l10n.none)
                                .multilineTextAlignment(.center)
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(x: 0.5, y: 0.5)
                        Text(l10n.loading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.startObserving()
        }
        .onDisappear {
            model.cancelObserving()
        }
        .foregroundColor(.secondary)
        .font(.callout)
    }
}

/// An app's name and how much energy it uses, on one line.
///
/// While the master switch is on, an app in the list of apps slowed down on battery shows a
/// tortoise next to its name all the time: in the accent colour while BatFi is slowing it
/// down, grey while it is not — on the charger, say, or while the app is in front. The
/// tortoise's tooltip, and what VoiceOver reads for it, says which, and why.
///
/// Pointing at the row blurs it and puts a button over it only where pressing the button
/// changes something right now — see `SlowDownMenuButton.offered` — that is, on battery
/// with an active licence: "Slow on battery" for an app BatFi can slow down that is not in
/// the list, "Stop slowing" for one it is slowing down at this moment. Anywhere else the row
/// stays as it is, so the grey tortoise stays in sight and its tooltip within reach. The button covers the row
/// rather than sitting under it, so the list keeps its height and the menu never jumps.
/// The button follows the status as it changes, so a charger plugged in under the pointer
/// takes it away at once.
struct BatteryTopCoalitionInfoItem: View {
    let coalition: Coalition
    /// Whether the row shows the tortoise: the master switch is on, the app is one BatFi can
    /// slow down, and it is in the list of apps slowed down on battery.
    let showsTortoise: Bool
    /// Whether BatFi is slowing the app down at this moment, and if not, why. Nil before the
    /// throttle manager has said.
    let status: SlowDownStatus?
    /// The button pointing at the row shows, if any.
    let button: SlowDownMenuButton?
    let toggleSlowDown: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var name: String { coalition.displayName ?? coalition.bundleIdentifier }
    private var showsButton: Bool { button != nil && isHovered }

    var body: some View {
        content
            // With Reduce Motion, the row only fades.
            .blur(radius: showsButton && !reduceMotion ? 3 : 0)
            .opacity(showsButton ? 0.5 : 1)
            .overlay {
                if showsButton, let button {
                    slowDownButton(button)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: showsButton)
            .contentShape(Rectangle())
            // Measured to fire inside the open menu, with BatFi not the active app.
            .onHover { isHovered = $0 }
            // The menu closing ends the hover without the pointer leaving the row, and the
            // row stays in the cached menu view: a stale button would greet the next opening.
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                isHovered = false
            }
            .onDisappear { isHovered = false }
            // VoiceOver has no pointer to hover with.
            .accessibilityActions {
                if let button {
                    Button(actionName(button), action: toggleSlowDown)
                }
            }
    }

    private var content: some View {
        HStack {
            Image(nsImage: coalition.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .frame(width: 24, height: 24)
            Text(name)
            if showsTortoise {
                Image(systemName: "tortoise.fill")
                    .font(.caption)
                    .foregroundStyle(status == .slowed ? AnyShapeStyle(Color.appAccent) : AnyShapeStyle(.secondary))
                    // Seen only where the row offers no button, or before the pointer reaches
                    // it: the button covers the tortoise and says the same first.
                    .menuTooltip(statusSentence)
                    .accessibilityLabel(statusSentence)
            }
            Spacer()
            HStack {
                Group {
                    switch coalition.energyImpact {
                    case 0..<300:
                        Text(L10n.Menu.HighEnergyUsage.medium)
                        Image(systemName: "gauge.with.dots.needle.33percent")
                    case 300..<900:
                        Text(L10n.Menu.HighEnergyUsage.high)
                        Image(systemName: "gauge.with.dots.needle.50percent")
                    case 900..<2000:
                        Text(L10n.Menu.HighEnergyUsage.veryHigh)
                        Image(systemName: "gauge.with.dots.needle.67percent")
                    default:
                        Text(L10n.Menu.HighEnergyUsage.batteryDraining)
                        Image(systemName: "gauge.with.dots.needle.100percent")
                    }
                }
                .font(.body)
            }
        }
    }

    private func slowDownButton(_ button: SlowDownMenuButton) -> some View {
        Button(action: toggleSlowDown) {
            switch button {
            case .slowDown:
                Label(L10n.EnergySaving.slowDownAction, systemImage: "tortoise")
            case .stopSlowing:
                Label(L10n.EnergySaving.stopSlowingAction, systemImage: "tortoise.fill")
            }
        }
        .buttonStyle(PrimaryButtonStyle(isLoading: false, isCompact: true))
        .menuTooltip(tooltip(button))
        // Reached through the row's accessibility action instead, which needs no hover.
        .accessibilityHidden(true)
    }

    /// For an app in the list, that it is slowed right now — the tooltip the button hides —
    /// then what the button does. For any other app, only what the button does.
    private func tooltip(_ button: SlowDownMenuButton) -> String {
        switch button {
        case .slowDown: actionName(button)
        case .stopSlowing: statusSentence + "\n" + actionName(button)
        }
    }

    private var statusSentence: String {
        let l10n = L10n.EnergySaving.self
        switch status {
        case .slowed: return l10n.appIsSlowedNow(name)
        case .notSlowed(.licence): return l10n.appIsNotSlowedWithoutLicense(name)
        case .notSlowed(.charger): return l10n.appIsNotSlowedWhilePluggedIn(name)
        case .notSlowed(.justUnplugged): return l10n.appIsNotSlowedJustUnplugged(name)
        case .notSlowed(.notRunning): return l10n.appIsNotSlowedNotRunning(name)
        case .notSlowed(.inUse): return l10n.appIsNotSlowedInUse(name)
        case .notSlowed(.audio): return l10n.appIsNotSlowedPlayingAudio(name)
        case .notSlowed(.quitting): return l10n.appIsNotSlowedQuitting(name)
        case .notSlowed(.refused): return l10n.appIsNotSlowedRefused(name)
        case .notSlowed(nil), nil: return l10n.appIsNotSlowedNow(name)
        }
    }

    /// The name of the row's accessibility action, and the last line of the button's tooltip.
    private func actionName(_ button: SlowDownMenuButton) -> String {
        switch button {
        case .slowDown: L10n.EnergySaving.slowDownAppOnBattery(name)
        case .stopSlowing: L10n.EnergySaving.stopSlowingAppOnBattery(name)
        }
    }
}
