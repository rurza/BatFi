//
//  About.swift
//  
//
//  Created by Adam on 21/06/2023.
//

import AboutKit
import Cocoa

public func presentAboutWindow() -> NSWindow {
    let about = AboutWindow(
        description: "Made with ❤️ and 🔋 by",
        customContent: {
            AboutViewAdditionalContentView()
        }
    )
    about.makeKeyAndOrderFront(nil)
    return about
}
