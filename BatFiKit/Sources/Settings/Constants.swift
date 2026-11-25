//
//  Constants.swift
//
//
//  Created by Adam on 05/05/2023.
//

import Foundation

/// The width of every pane's content. The window takes its width from the pane — this plus
/// `Container`'s 30 pt margins on each side, so 650 pt — and the toolbar has to fit in it:
/// at 650 pt every language's nine tab titles fit without an overflow chevron, German being
/// the tightest, with no room to spare. Adding a pane, or a longer tab title in any
/// language, needs that checked again.
let settingsContentWidth: Double = 590
