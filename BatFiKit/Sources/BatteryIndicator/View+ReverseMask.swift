//
//  View+ReverseMask.swift
//
//
//  Created by Adam on 18/05/2023.
//

import SwiftUI

public extension View {
    @inlinable
    func reverseMask(
        alignment: Alignment = .center,
        @ViewBuilder _ mask: () -> some View
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    mask()
                        .blendMode(.destinationOut)
                }
        }
    }
}
