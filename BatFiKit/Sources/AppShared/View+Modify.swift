//
//  View+Modify.swift
//
//
//  Created by Adam on 17/09/2023.
//

import Charts
import Foundation
import SwiftUI

public extension View {
    func modify<Content>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}

public extension ChartContent {
    func modify<Content>(@ChartContentBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}
