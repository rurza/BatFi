//
//  SeparatorView.swift
//  Vetero
//
//  Created by Adam on 07/05/2023.
//

import SwiftUI

public struct SeparatorView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            Rectangle().frame(height: 1)
                .foregroundColor(Color.white)
                .opacity(colorScheme == .light ? 0.3 : 0)
        }
    }
}

struct SeparatorView_Previews: PreviewProvider {
    static var previews: some View {
        SeparatorView()
    }
}
