//
//  TempOverrideDebugView.swift
//
//
//  Created by Adam Różyński on 12/04/2024.
//

#if DEBUG

import Clients
import Defaults
import DefaultsKeys
import Dependencies
import Shared
import SwiftUI

struct TempOverrideDebugView: View {

    @Dependency(\.appChargingState) var chargingState
    @Default(.chargeLimit) private var chargeLimit
    @State private var overrideLimit: Double?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(
                overrideLimit == nil ? "Enable override" : "Override \(overrideLimit!)",
                isOn: .init(
                    get: { overrideLimit != nil }, set: { on in
                        if on {
                            overrideLimit = Double(chargeLimit)
                        } else {
                            overrideLimit = nil
                        }
                    }
                )
            )
            Slider(
                value: .init(get: { overrideLimit ?? 100 }, set: { overrideLimit = $0 }), in: 0...100, step: 5)
            .disabled(overrideLimit == nil)
            .labelsHidden()
            .task {
                if let limit = await chargingState.currentUserTempOverrideMode()?.limit {
                    overrideLimit = Double(limit)
                }

            }
            .onChange(of: overrideLimit) { limit in
                Task {
                    if let limit {
                        await chargingState.setTempOverride(.init(limit: Int(limit)))
                    } else {
                        await chargingState.setTempOverride(nil)
                    }
                }
            }
        }
    }
}

#endif
