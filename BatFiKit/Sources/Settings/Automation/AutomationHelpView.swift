//
//  AutomationHelpView.swift
//  BatFi
//
//  Localized explanation of the calendar/automation feature, shown in a popover from the
//  help button in the Automation pane.
//

import L10n
import SwiftUI

struct AutomationHelpView: View {
    private var points: [String] {
        [
            L10n.Automation.helpRules,
            L10n.Automation.helpConditions,
            L10n.Automation.helpPriority,
            L10n.Automation.helpMenu,
            L10n.Automation.helpLocation,
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Automation.helpHeading)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(point)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 340)
    }
}
