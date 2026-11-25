//
//  OnboardingFooterLayout.swift
//  BatFiKit
//

import SwiftUI

/// The onboarding footer: a button at each edge and the page dots centred between them.
///
/// The dots stay centred unless a long button title would run into them, as starting the
/// trial does in several languages; then they step aside just enough to keep clear of it.
struct OnboardingFooterLayout: Layout {
    enum Role: LayoutValueKey {
        static let defaultValue = Kind.pageControl

        enum Kind {
            case pageControl
            case leading
            case trailing
        }
    }

    /// The least room kept between the dots and a button.
    private let gap: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        let width = proposal.width ?? sizes.map(\.width).reduce(0, +) + gap * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var leadingEdge = bounds.minX
        var trailingEdge = bounds.maxX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            switch subview[Role.self] {
            case .leading:
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                leadingEdge = bounds.minX + size.width
            case .trailing:
                subview.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(size))
                trailingEdge = bounds.maxX - size.width
            case .pageControl:
                break
            }
        }
        for subview in subviews where subview[Role.self] == .pageControl {
            let size = subview.sizeThatFits(.unspecified)
            let half = size.width / 2
            var x = min(bounds.midX, trailingEdge - gap - half)
            x = max(x, leadingEdge + (leadingEdge > bounds.minX ? gap : 0) + half)
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(size))
        }
    }
}
