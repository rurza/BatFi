//
//  ChargingModeSymbol.swift
//  
//
//  Created by Adam on 23/05/2023.
//

import SwiftUI

struct ChargingModeSymbol: View {
    @ObservedObject var model: BatteryIndicatorView.Model
    let height: Double
    let heightFraction: Double

    var body: some View {
        let height = fontSize(height: height, fraction: heightFraction)
        Group {
            if case .charging = model.chargingMode {
                Image(systemName: "bolt.fill")
                    .transition(.opacity)
            } else if case .inhibited = model.chargingMode {
                Image(systemName: "pause.fill")
                    .transition(.opacity)
            }
        }
        .font(.system(size: height, weight: .medium))
    }
}
