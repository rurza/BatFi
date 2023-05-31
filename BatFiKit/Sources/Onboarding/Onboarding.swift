//
//  Onboarding.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import Foundation
import SwiftUI

struct Onboarding<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var index = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { scrollView in
                        HStack {
                            content()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .frame(width: proxy.size.width)
                        }
                        .onChange(of: index) { newValue in
                            withAnimation(.easeInOut(duration: 2)) {
                                scrollView.scrollTo(newValue)
                            }
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                PageControl(count: 3, index: $index)
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }

        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding {
            Text("Hello world")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.green)
                .id(0)
            Image(systemName: "globe")
                .id(1)
        }
    }
}
