//
//  OnboardingWindow.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Cocoa
import Defaults
import SwiftUI

public class OnboardingWindow: NSWindow {
    public init(_ installHelper: @escaping () -> Void) {
        let vc = NSHostingController(rootView: Onboarding(didInstallHelper: installHelper))
        vc.sizingOptions = [.preferredContentSize]
        let windowMask: NSWindow.StyleMask
        if Defaults[.onboardingIsDone] {
            windowMask = [.miniaturizable, .closable, .titled, .fullSizeContentView]
        } else {
            windowMask = [.miniaturizable, .titled, .fullSizeContentView]
        }
        super.init(
            contentRect: NSRect(origin: .zero, size: vc.view.fittingSize),
            styleMask: windowMask,
            backing: .buffered,
            defer: false
        )
        self.contentViewController = vc
        self.isReleasedWhenClosed = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.title = "Onboarding"
        self.animationBehavior = .documentWindow
    }
}
