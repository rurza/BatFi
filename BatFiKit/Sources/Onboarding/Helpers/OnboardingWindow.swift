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
    private let onClose: () -> Void

    public init(_ installHelper: @escaping () -> Void, onClose: @escaping () -> Void) {
        let vc = NSHostingController(rootView: Onboarding(didInstallHelper: installHelper))
        vc.sizingOptions = [.preferredContentSize]
        let windowMask: NSWindow.StyleMask
        if Defaults[.onboardingIsDone] {
            windowMask = [.miniaturizable, .closable, .titled, .fullSizeContentView]
        } else {
            windowMask = [.miniaturizable, .titled, .fullSizeContentView]
        }
        self.onClose = onClose
        super.init(
            contentRect: NSRect(origin: .zero, size: vc.view.fittingSize),
            styleMask: windowMask,
            backing: .buffered,
            defer: false
        )
        contentViewController = vc
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "Onboarding"
        animationBehavior = .documentWindow
    }

    public override func close() {
        self.onClose()
        super.close()
    }
}
