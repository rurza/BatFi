//
//  WelcomeView.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import SwiftUI

struct WelcomeView: View {

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Extend the life of your battery.")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi helps you optimize your macOS battery performance by managing charging levels intelligently – charging to 100% only when it's needed.")
                    .padding(.bottom, 60)
            }
        }
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .frame(width: 420, height: 600)
            .preferredColorScheme(.dark)
    }
}
