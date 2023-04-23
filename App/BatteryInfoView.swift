//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI

struct BatteryInfoView: View {
    @ObservedObject var batteryLevelObserver: BatteryLevelObserver
    private let itemsSpace: CGFloat  = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Battery")
                    .fontWeight(.semibold)
                Spacer(minLength: itemsSpace)
                Group {
                    if let batteryLevel = batteryLevelObserver.batteryLevel {
                        Text("\(batteryLevel)%")
                    } else {
                        Text("Unknown status")
                    }
                }
                .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
            Group {
                HStack {
                    Text("Power source:")
                    Spacer(minLength: itemsSpace)
                    Group {
                        if let powerSource = batteryLevelObserver.powerSource {
                            Text(powerSource)
                        } else {
                            Text("Unknown status")
                        }
                    }.foregroundColor(.secondary)
                }
                if let timeLeftString = batteryLevelObserver.timeLeftString {
                    HStack {
                        Text("Time left:")
                        Spacer(minLength: itemsSpace)
                        Text(timeLeftString)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 200)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

