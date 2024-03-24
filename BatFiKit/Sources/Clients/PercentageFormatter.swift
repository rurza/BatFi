//
//  PercentageFormatter.swift
//
//
//  Created by Adam Różyński on 24/03/2024.
//

import Dependencies
import Foundation

#warning("implement")
public struct PercentageFormatter: TestDependencyKey {
    public var string: @Sendable (_ value: Int) -> String

    public static var testValue: PercentageFormatter = .init(string: { _ in unimplemented("string not implemented") })
}

public extension DependencyValues {
    var percentageFormatter: PercentageFormatter {
        get { self[PercentageFormatter.self] }
        set { self[PercentageFormatter.self] = newValue }
    }
}
