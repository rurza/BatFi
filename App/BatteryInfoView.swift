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
                    .bold()
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
            HStack {
                Text("Is charging:")
                    .bold()
                Spacer(minLength: 20)
                Group {
                    if let isCharging = batteryLevelObserver.isCharging {

                        if isCharging {
                            Text("charging")
                        } else {
                            Text("not charging")
                        }

                    } else {
                        Text("Unknown status")
                    }
                }.foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

