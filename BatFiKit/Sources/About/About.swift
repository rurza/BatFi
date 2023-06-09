//
//  About.swift
//  
//
//  Created by Adam on 21/06/2023.
//

import AboutKit
import L10n
import Cocoa

public func presentAboutWindow() -> NSWindow {
    let about = AboutWindow(
        description: L10n.About.Label.aboutDescription,
        customContent: {
            AboutViewAdditionalContentView()
        }
    )
    about.makeKeyAndOrderFront(nil)
    return about
}
