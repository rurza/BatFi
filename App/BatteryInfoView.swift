//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI

struct BatteryInfoView: View {
    @ObservedObject var batteryLevelObserver: BatteryLevelObserver

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Battery")
                    .fontWeight(.semibold)
                Spacer()
                Group {
                    if let batteryLevel = batteryLevelObserver.batteryLevel {
                        Text("\(batteryLevel)%")
                    } else {
                        Text("Unknown status")
                    }
                }
                .foregroundColor(.secondary)
            }.frame(maxWidth: .infinity)
            Group {
                HStack {
                    Text("Power source:")
                    Spacer(minLength: 20)
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
                        Spacer(minLength: 20)
                        Text(timeLeftString)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

