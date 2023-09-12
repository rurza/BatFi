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
        HStack {
            Circle().frame(width: 8, height: 8)
                .foregroundStyle(color)
                .shadow(color: .black, radius: 6, x: 0, y: 4)
            Text(label)
        }
        .foregroundColor(Color.secondary)
        .font(.callout)
    }
}
