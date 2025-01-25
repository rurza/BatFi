//
//  LicenseWindow.swift
//  BatFiKit
//
//  Created by Adam Różyński on 24/01/2025.
//

import AppKit
import SwiftUI

public final class LicenseWindow: NSWindow {
    public init(model: LicenseModel) {
        let vc = NSHostingController(rootView: LicenseView(model: model))
        vc.sizingOptions = [.preferredContentSize]
        super.init(
            contentRect: NSRect(origin: .zero, size: vc.view.fittingSize),
            styleMask: [.miniaturizable, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        contentViewController = vc
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "BatFi License"
    }
}
