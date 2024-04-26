//
//  StatusItemManager.swift
//
//
//  Created by Adam on 18/05/2023.
//

import AppShared
import AsyncAlgorithms
import BatteryIndicator
import Combine
import Clients
import Cocoa
import DefaultsKeys
import Dependencies
import SnapKit
import SwiftUI

@MainActor
public protocol StatusItemManagerDelegate: AnyObject {
    func statusItemIconDidAppear()
}

@MainActor
public final class StatusItemManager {
    public weak var delegate: StatusItemManagerDelegate?
    private var didAppear = false

    let statusItem: NSStatusItem

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setUp()
    }

    weak var batteryIndicatorView: NSView?
    private lazy var batteryIndicatorModel = BatteryIndicatorView.Model()
    private lazy var statusItemModel = StatusItem.Model()

    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?

    func setUp() {
        guard let button = statusItem.button else { fatalError() }
        let hostingView = NSHostingView(
            rootView: StatusItem(
                sizePassthrough: sizePassthrough,
                batteryIndicatorModel: batteryIndicatorModel,
                model: statusItemModel
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 38, height: 13)
        button.frame = hostingView.frame
        hostingView.wantsLayer = true
        button.addSubview(hostingView)
        self.batteryIndicatorView = hostingView
        sizeCancellable = sizePassthrough.sink { [weak self] size in
            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
            self?.batteryIndicatorView?.frame = frame
            self?.statusItem.button?.frame = frame
        }
        delegate?.statusItemIconDidAppear()
    }
}
