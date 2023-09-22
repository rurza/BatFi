import Defaults
import L10n
import SettingsKit
import SwiftUI

struct MenuView: View {
    @Default(.showPowerDiagram) private var showPowerDiagram
    
    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.powerDiagram) {
                Toggle(l10n.Button.Label.powerDiagramShow, isOn: $showPowerDiagram)
            }
        }
    }
    
    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Menu"),
            title: L10n.Settings.Tab.Title.menu,
            toolbarIcon: NSImage(
                systemSymbolName: "line.3.horizontal.circle.fill",
                accessibilityDescription: L10n.Settings.Accessibility.Title.menu
            )!
        ) {
            Self()
        }
    }()
}
