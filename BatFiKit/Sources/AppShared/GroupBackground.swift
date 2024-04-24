//
//  GroupBackground.swift
//
//
//  Created by Adam Różyński on 24/04/2024.
//

import SwiftUI

public struct GroupBackground<Content: View>: View {
    var content: Content
    @Environment(\.colorScheme) private var colorScheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .foregroundColor(colorScheme == .light ? .white.opacity(0.7) : .white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colorScheme == .light ? .black.opacity(0.08) : .white.opacity(0.05), lineWidth: 1)
                    }
            }
    }
}
