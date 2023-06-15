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
            Image("Icon", bundle: Bundle.module)
                .resizable()
                .frame(width: 300, height: 300)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text("Extend the life of your Mac.")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi helps you optimize your macOS battery performance by managing charging levels intelligently, yet giving you full control – charging to 100% only when it's needed.")
                    .padding(.bottom, 30)
            }
        }
        .padding(20)

    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .frame(width: 420, height: 600)
            .preferredColorScheme(.dark)
    }
}
