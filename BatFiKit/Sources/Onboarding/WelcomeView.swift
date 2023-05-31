//
//  WelcomeView.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import SwiftUI

struct WelcomeView: View {
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Extend the life of your battery.")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi helps you optimize your macOS battery performance by managing charging levels intelligently")
                    .padding(.bottom, 60)
                Button(action: action) {
                    Text("Get started")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black, radius: 8, x: 0, y: 6)

                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(action: {})
            .frame(width: 420, height: 600)
    }
}
