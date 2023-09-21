//
//  BetaLabel.swift
//  
//
//  Created by Adam on 11/05/2023.
//

import SwiftUI

struct BetaLabel: View {
    let disabled: Bool

    var body: some View {
        Text("BETA")
            .font(.footnote)
            .padding(.vertical, 1)
            .padding(.horizontal, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(lineWidth: 1)
            }
            .foregroundColor(.secondary)
            .opacity(disabled ? 0.4 : 1)
    }
}

extension View {
    func withBetaLabel(disabled: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            BetaLabel(disabled: disabled)
            self
        }
    }
}
