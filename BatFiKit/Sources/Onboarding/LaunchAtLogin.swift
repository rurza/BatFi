//
//  LaunchAtLogin.swift
//  
//
//  Created by Adam on 02/06/2023.
//

import Defaults
import DefaultsKeys
import SwiftUI

struct LaunchAtLogin: View {
    @Default(.launchAtLogin) private var launchAtLogin

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Launch at login")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi will automatically launch when you log in.")
                    .frame(maxWidth: .infinity, alignment: .leading) // required, otherwise it will render in center, SwiftUI bug
                    .padding(.bottom, 20)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .padding(.bottom, 60)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct LaunchAtLogin_Previews: PreviewProvider {
    static var previews: some View {
        LaunchAtLogin()
            .frame(width: 420, height: 600)
    }
}
