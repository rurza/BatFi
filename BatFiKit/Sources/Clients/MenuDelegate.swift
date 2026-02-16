//
//  MenuDelegate.swift
//
//
//  Created by Adam on 06/11/2023.
//

import AppKit
import Dependencies

public struct MenuDelegate: TestDependencyKey, Sendable {
    public var observeMenu: @Sendable () async -> AsyncStream<Bool>

    public init(observeMenu: @escaping @Sendable () async -> AsyncStream<Bool>) {
        self.observeMenu = observeMenu
    }

    nonisolated(unsafe) public static var testValue: MenuDelegate = unimplemented()
}

public extension DependencyValues {
    var menuDelegate: MenuDelegate {
        get { self[MenuDelegate.self] }
        set { self[MenuDelegate.self] = newValue }
    }
}

@MainActor
public final class MenuObserver: NSObject, NSMenuDelegate {
    @Published
    public private(set) var menuIsOpened: Bool = false

    public static let shared = MenuObserver()

    public func menuWillOpen(_: NSMenu) {
        menuIsOpened = true
    }

    public func menuDidClose(_: NSMenu) {
        menuIsOpened = false
    }
}
