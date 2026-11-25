//
//  SlowedAppsSettings.swift
//  BatFi
//
//  The "Apps on battery" section of the Energy pane: the master switch for slowing apps
//  down on battery, and the list of apps it slows.
//

import AppKit
import AppShared
import Defaults
import DefaultsKeys
import L10n
import SettingsKit
import Shared
import SharedUI
import SwiftUI
import UniformTypeIdentifiers

/// The master switch, the apps it slows down with the mode of each, and "Add App…".
///
/// Only edits the stored settings: BatFi's throttle manager follows them by itself, slowing
/// down or giving back as they change.
///
/// Shows up to three rows and asks the settings window to fit when that count changes.
struct SlowedAppsSettings: View {
    @Default(.slowDownAppsOnBattery) private var slowDownAppsOnBattery
    @Default(.slowedOnBatteryApps) private var slowedApps
    @State private var isDropTargeted = false
    @State private var settingsWindow: NSWindow?

    private static let width: CGFloat = 460
    private static let rowHeight: CGFloat = 36

    /// The set `AppThrottleClient` passes: BatFi, release or beta, is never slowed down.
    private static let ownBundleIDs = Set([Constant.appBundleIdentifier, Bundle.main.bundleIdentifier].compactMap { $0 })

    var body: some View {
        let l10n = L10n.EnergySaving.self
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $slowDownAppsOnBattery) {
                Text(l10n.slowDownToggle)
                    .withBetaLabel()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(l10n.slowDownFootnote)
                .fixedSize(horizontal: false, vertical: true)
                .settingDescription()
            if !rows.isEmpty {
                appList
                    .opacity(slowDownAppsOnBattery ? 1 : 0.4)
                    .disabled(!slowDownAppsOnBattery)
            }
            HStack {
                dropTarget
                Button {
                    addApps()
                } label: {
                    Label(l10n.slowDownAddApp, systemImage: "plus")
                }
                .disabled(!slowDownAppsOnBattery)
            }
            .fixedSize(horizontal: false, vertical: true)
            if SlowedApps.usesAlways(slowedApps) {
                alwaysWarning
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .background(WindowReader { settingsWindow = $0 })
        .onChange(of: slowedApps) { _, _ in resizeSettingsWindow() }
    }

    // MARK: - The list

    private struct Row: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage
        var id: String { bundleID }
    }

    /// The slowed apps by name. An app no longer installed shows its bundle identifier and a
    /// generic icon, so it can still be taken out.
    private var rows: [Row] {
        slowedApps.keys
            .map { bundleID in
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                return Row(
                    bundleID: bundleID,
                    name: url.flatMap(Self.appName(at:)) ?? bundleID,
                    icon: url.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
                        ?? NSWorkspace.shared.icon(for: .applicationBundle)
                )
            }
            .sorted { lhs, rhs in
                switch lhs.name.localizedStandardCompare(rhs.name) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: lhs.bundleID < rhs.bundleID
                }
            }
    }

    private var appList: some View {
        let rows = rows
        return GroupBackground {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        appRow(row)
                            .frame(height: Self.rowHeight)
                            .overlay(alignment: .bottom) {
                                if row.id != rows.last?.id {
                                    Divider().padding(.leading, 38)
                                }
                            }
                    }
                }
            }
            .frame(height: CGFloat(min(rows.count, 3)) * Self.rowHeight)
        }
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .overlay {
                Label(L10n.EnergySaving.slowDownDropApps, systemImage: "arrow.down.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                let apps = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "app" }
                guard !apps.isEmpty else { return false }
                add(apps, window: settingsWindow)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .disabled(!slowDownAppsOnBattery)
            .accessibilityLabel(L10n.EnergySaving.slowDownDropApps)
    }

    private func resizeSettingsWindow() {
        DispatchQueue.main.async { [weak settingsWindow] in
            guard let settingsWindow, let contentView = settingsWindow.contentView else { return }
            contentView.layoutSubtreeIfNeeded()
            let contentSize = contentView.fittingSize
            let targetFrame = settingsWindow.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
            let oldFrame = settingsWindow.frame
            guard abs(oldFrame.height - targetFrame.height) > 1 else { return }
            settingsWindow.setFrame(
                NSRect(x: oldFrame.minX, y: oldFrame.maxY - targetFrame.height,
                       width: oldFrame.width, height: targetFrame.height),
                display: true,
                animate: true
            )
        }
    }

    private func appRow(_ row: Row) -> some View {
        let l10n = L10n.EnergySaving.self
        return HStack(spacing: 8) {
            Image(nsImage: row.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(row.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Picker(selection: mode(of: row.bundleID)) {
                Text(l10n.slowDownModeBackgroundOnly).tag(SlowDownMode.backgroundOnly)
                Text(l10n.slowDownModeAlways).tag(SlowDownMode.always)
            } label: {
                // VoiceOver's name for the picker; the row already shows it.
                Text(row.name)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help(l10n.slowDownAlwaysWarning)
            Button {
                slowedApps = SlowedApps.removing(row.bundleID, from: slowedApps)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(l10n.slowDownRemoveApp(row.name))
            .accessibilityLabel(l10n.slowDownRemoveApp(row.name))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func mode(of bundleID: String) -> Binding<SlowDownMode> {
        Binding(
            get: { slowedApps[bundleID] ?? SlowedApps.defaultMode },
            set: { slowedApps = SlowedApps.setting($0, for: bundleID, in: slowedApps) }
        )
    }

    // MARK: - "Always"

    private var alwaysWarning: some View {
        return Label {
            Text(L10n.EnergySaving.slowDownAlwaysWarning)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .settingDescription()
    }

    // MARK: - Add App…

    private func addApps() {
        let panel = NSOpenPanel()
        panel.message = L10n.EnergySaving.slowDownAddAppPanelMessage
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let window = NSApp.keyWindow
        Task { @MainActor in
            let response: NSApplication.ModalResponse
            if let window {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK else { return }
            add(panel.urls, window: window)
        }
    }

    /// Adds the chosen apps that BatFi may slow down, and says which ones it won't, and why.
    private func add(_ urls: [URL], window: NSWindow?) {
        var added = [String]()
        var refused = [(name: String, reason: ThrottleEligibility.AddRefusal)]()
        for url in urls {
            let bundle = Bundle(url: url)
            let eligible = ThrottleEligibility.canOfferActions(
                bundleID: bundle?.bundleIdentifier,
                bundleURL: url,
                ownBundleIDs: Self.ownBundleIDs
            )
            let refusal = ThrottleEligibility.addRefusal(
                eligible: eligible,
                declaresNoDockIcon: ThrottleEligibility.declaresNoDockIcon(bundle?.infoDictionary)
            )
            if let refusal {
                refused.append((Self.appName(at: url) ?? url.deletingPathExtension().lastPathComponent, refusal))
            } else if let bundleID = bundle?.bundleIdentifier {
                added.append(bundleID)
            }
        }
        slowedApps = SlowedApps.adding(added, to: slowedApps)

        guard !refused.isEmpty else { return }
        // One reason per kind of refusal among the apps chosen, in a fixed order.
        let reasons = [ThrottleEligibility.AddRefusal.notEligible, .noDockIcon]
            .filter { reason in refused.contains { $0.reason == reason } }
            .map { reason in
                switch reason {
                case .notEligible: L10n.EnergySaving.slowDownCannotAddMessage
                case .noDockIcon: L10n.EnergySaving.slowDownCannotAddNoDockIcon
                }
            }
        let alert = NSAlert()
        alert.messageText = L10n.EnergySaving.slowDownCannotAddTitle(refused.map(\.name).formatted(.list(type: .and)))
        alert.informativeText = reasons.joined(separator: "\n")
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// The name the app goes by, as the high-energy list in the menu shows it.
    private static func appName(at url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.localizedInfoDictionary?[kCFBundleNameKey as String] as? String
            ?? bundle.infoDictionary?[kCFBundleNameKey as String] as? String
    }
}

private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: WindowReaderView, context: Context) {
        view.onWindow = onWindow
    }

    final class WindowReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
