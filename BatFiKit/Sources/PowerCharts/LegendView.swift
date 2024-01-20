//
//  LegendView.swift
//
//
//  Created by Adam on 12/09/2023.
//

import SwiftUI

struct LegendView: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundColor(color)
                .overlay {
                    Circle().stroke(lineWidth: 1)
                }
            Text(label)
        }
        .foregroundColor(Color.secondary)
        .font(.callout)
    }
}
