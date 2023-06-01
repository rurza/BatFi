//
//  FinalView.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Defaults
import DefaultsKeys
import Foundation
import SwiftUI

struct FinalView: View {
    @Default(.launchAtLogin) private var launchAtLogin

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Almost done.")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi will automatically launch when you log in to your macOS system")
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .padding(.bottom, 60)
                Text("Installing the helper tool requires admin permissions and is essential for BatFi's functionality.")
                    .padding(.bottom, 20)
            }
        }
    }
}
