//
//  MenuTooltipPlacement.swift
//  BatFi
//

import CoreGraphics

/// Where BatFi's own menu tooltip goes on screen.
///
/// Like a macOS tooltip it sits just below what it explains, centred under it. Where the
/// screen ends below — a menu that reaches down to the Dock, say — it goes just above
/// instead. Sideways it slides along so it stays whole on the element's screen, and a
/// tooltip that fits neither below nor above stays on the screen too, over the element if
/// need be: half a sentence is no use to anyone.
///
/// Everything is in AppKit's screen coordinates, with y growing upwards.
public enum MenuTooltipPlacement {
    /// The space between the element and its tooltip.
    public static let gap: CGFloat = 4

    /// - Parameters:
    ///   - size: The tooltip's size.
    ///   - element: The element's frame on screen.
    ///   - screen: The part of the element's screen a window may use: its visible frame.
    public static func frame(for size: CGSize, below element: CGRect, within screen: CGRect) -> CGRect {
        let x = clamp(element.midX - size.width / 2, from: screen.minX, to: screen.maxX - size.width)
        let below = element.minY - gap - size.height
        let above = element.maxY + gap
        let y: CGFloat
        if below >= screen.minY {
            y = below
        } else if above + size.height <= screen.maxY {
            y = above
        } else {
            y = clamp(below, from: screen.minY, to: screen.maxY - size.height)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Which side of its element a tooltip placed by `frame(for:below:within:)` ended up on.
    public enum Side: Sendable, Equatable {
        case below
        case above
    }

    /// The side of `element` that `tooltip` is on: the side it grows out of when it appears.
    /// One pushed over its element by a short screen counts by its middle.
    public static func side(of tooltip: CGRect, from element: CGRect) -> Side {
        tooltip.midY <= element.midY ? .below : .above
    }

    /// `value` kept within `lower...upper`; `lower` wins when the two cross, so a tooltip
    /// wider or taller than the screen starts at its left or bottom edge.
    private static func clamp(_ value: CGFloat, from lower: CGFloat, to upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}
