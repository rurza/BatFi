//
//  Onboarding.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import SwiftUI

struct Onboarding: View {
    @State private var index: Int = 0
    let numberOfPages = 3

    var body: some View {
        VStack {
            PageView(
                numberOfPages: numberOfPages,
                index: $index
            ) {
                WelcomeView().id(0)
                ChargingLimitView().id(1)
            }
            HStack {
                Button(
                    action: {
                        index -= 1
                    }
                ) {
                    Text("Previous")
                }
                .buttonStyle(.onboarding)
                .opacity(index != 0 ? 1 : 0)
                .animation(.spring(), value: index)
                Spacer()
                Button(
                    action: {
                        switch index {
                        case 2:
                            break
                        default:
                            index += 1
                        }
                    }
                ) {
                    switch index {
                    case 0:
                        Text("Get started")
                    case 2:
                        Text("Install Helper")
                    default:
                        Text("Next")
                    }
                }
                .buttonStyle(.onboarding)
                .animation(.spring(), value: index)
            }.overlay(alignment: .center) {
                PageControl(count: 3, index: $index)
            }
        }
        .padding(20)
        .preferredColorScheme(.dark)
        .frame(width: 420, height: 600)
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding()
            .frame(width: 420, height: 600)
    }
}
