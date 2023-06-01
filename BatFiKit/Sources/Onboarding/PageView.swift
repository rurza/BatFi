//
//  PageView.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import Foundation
import SwiftUI

struct PageView<Content: View>: View {
    let numberOfPages: Int
    @Binding var index: Int
    @ViewBuilder let content: () -> Content

    @State private var offset: CGPoint = .zero
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OffsetObservingScrollView(
                    axes: .horizontal,
                    showsIndicators: false,
                    offset: $offset) {
                        ScrollViewReader { scrollView in
                            HStack(spacing: 0) {
                                content()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .frame(width: proxy.size.width)
                            }
                            .onChange(of: index) { newValue in
                                withAnimation {
                                    scrollView.scrollTo(newValue)
                                }
                            }
                        }
                    }
                .frame(width: proxy.size.width, height: proxy.size.height)
               
            }
        }
    }
}

struct PageView_Previews: PreviewProvider {
    static var previews: some View {
        PageView(
            numberOfPages: 2,
            index: .constant(0)
        ) {
            Text("Hello world")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.green)
                .id(0)
            Image(systemName: "globe")
                .id(1)
        }
    }
}
