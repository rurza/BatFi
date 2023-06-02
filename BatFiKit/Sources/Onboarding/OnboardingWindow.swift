//
//  OnboardingWindow.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Cocoa
import SwiftUI

public class OnboardingWindow: NSWindow {
    public init(_ installHelper: @escaping () -> Void) {
        let vc = NSHostingController(rootView: Onboarding(didInstallHelper: installHelper))
        vc.sizingOptions = [.preferredContentSize]
        super.init(contentRect: NSRect(origin: .zero, size: vc.view.fittingSize), styleMask: [.miniaturizable, .titled], backing: .buffered, defer: false)
        self.contentViewController = vc
        self.isReleasedWhenClosed = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.title = "Onboarding"
        self.animationBehavior = .documentWindow
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.makeKeyAndOrderFront(sender)
    }

    public override func orderFront(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.orderFront(sender)
    }
}
