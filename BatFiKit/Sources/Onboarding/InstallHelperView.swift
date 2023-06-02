//
//  FinalView.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Foundation
import SwiftUI

struct InstallHelperView: View {

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Almost done.")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi will install helper tool, that will work in background and is able to change your computer's charging model.")
                    .padding(.bottom, 30)
                Text("Installing the helper tool requires admin permissions and is essential for BatFi's functionality.")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }
        }
    }
}
