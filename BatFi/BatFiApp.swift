//
//  BatFiApp.swift
//  BatFi
//
//  Created by Adam on 11/04/2023.
//

import ServiceManagement
import SwiftUI

@main
struct BatFiApp: App {
    @State private var chargingDisabled = false

    var body: some Scene {
        MenuBarExtra {
            Button {
                Task.detached {
                    let service = SMAppService.daemon(plistName: "software.micropixels.BatFi.helper.plist")
                    do {
                        print("will register, status: \(service.status.rawValue)")
                        try service.register()
                        print("did register")
                    } catch {
                        print("did not register, error: \(error)")
                    }
                }
            } label: {
                Text("Install helper tool")
            }
        } label: {
            if chargingDisabled {
                Image(systemName: "minus.plus.batteryblock")
            } else {
                Image(systemName: "bolt.batteryblock.fill")

            }
        }
        .onChange(of: chargingDisabled) { disable in
            // sudo smc -k CH0B -w 02
            // sudo smc -k CH0C -w 02
           
        }

    }
}
