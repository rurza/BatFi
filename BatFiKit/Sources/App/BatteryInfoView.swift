//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI

struct BatteryInfoView: View {
    private let itemsSpace: CGFloat  = 30
    @StateObject private var chargingObserver = ChargingObserver()

    var body: some View {
        if let powerState = chargingObserver.powerState {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Battery")
                        .fontWeight(.semibold)
                    Spacer(minLength: itemsSpace)
                    Group {
                        if let batteryLevel = powerState.batteryLevel {
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
                            if let powerSource = powerState.powerSource {
                                Text(powerSource)
                            } else {
                                Text("Unknown status")
                            }
                        }.foregroundColor(.secondary)
                    }
                    if let timeLeft = powerState.timeLeft {
                        HStack {
                            Text("Time left:")
                            Spacer(minLength: itemsSpace)
                            Group {
                                Text("\(timeLeft)")
                            }
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
}

struct BatteryInfoView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryInfoView()
    }
}
