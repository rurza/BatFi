//
//  MenuTooltip.swift
//  BatFi
//

import AppKit
import AppShared
import SwiftUI

extension View {
    /// Shows `text` in a tooltip of BatFi's own once the pointer has rested on the view for
    /// half a second, in place of `.help`.
    ///
    /// Inside the open status menu `.help` tooltips often never appear: BatFi is not the
    /// active app while its menu is open, and the system's tooltips are unreliable there.
    /// `.onHover`, though, is measured to fire in the menu all the same, so this one is
    /// driven by hover and drawn in a panel of its own above the menu. Being a window of its
    /// own, it is never clipped by the menu item and never changes the menu's height.
    ///
    /// It fades in growing out of the element's side, and fades out as soon as the pointer
    /// leaves or the view goes away (a button taken away when the charger is plugged in,
    /// say). It vanishes at once with the menu, so it is never left on screen without its
    /// element. Only one is ever shown: a new one takes the panel over.
    ///
    /// It is for the pointer only. VoiceOver never sees it, so say the same in the view's
    /// accessibility label or action where it matters.
    public func menuTooltip(_ text: String) -> some View {
        modifier(MenuTooltipModifier(text: text))
    }
}

private struct MenuTooltipModifier: ViewModifier {
    let text: String
    @State private var tooltip = MenuTooltip()

    func body(content: Content) -> some View {
        content
            .background(MenuTooltipAnchor(tooltip: tooltip))
            .onHover { isHovered in
                if isHovered {
                    tooltip.schedule(text)
                } else {
                    tooltip.dismiss()
                }
            }
            .onChange(of: text) { _, text in
                tooltip.update(text)
            }
            // The menu closing ends the hover without the pointer leaving the view. The menu
            // is gone at once, and its tooltip goes with it rather than fading after it.
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                tooltip.dismiss(animated: false)
            }
            .onDisappear { tooltip.dismiss() }
    }
}

/// One view's tooltip: when it is due, and where its view is.
@MainActor
private final class MenuTooltip {
    /// How long the pointer rests on the view before the tooltip shows.
    static let delay: Duration = .milliseconds(500)

    /// The view's stand-in in AppKit, which knows the view's window and frame.
    weak var anchor: NSView?
    private var text = ""
    private var pending: Task<Void, Never>?

    func schedule(_ text: String) {
        self.text = text
        pending?.cancel()
        // A task on the main actor, not a `Timer`: the main queue is served while the menu
        // tracks the pointer, a default-mode timer is not.
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    /// Takes a new text, into the tooltip already on screen too.
    func update(_ text: String) {
        self.text = text
        if MenuTooltipPanel.shared.owner === self {
            show()
        }
    }

    func dismiss(animated: Bool = true) {
        pending?.cancel()
        pending = nil
        MenuTooltipPanel.shared.hide(for: self, animated: animated)
    }

    private func show() {
        guard let anchor, let window = anchor.window, window.isVisible else { return }
        let element = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        guard let screen = window.screen ?? NSScreen.main else { return }
        MenuTooltipPanel.shared.show(text, for: self, below: element, within: screen.visibleFrame)
    }
}

/// An empty view behind the element that hands its AppKit self to the tooltip, and
/// dismisses the tooltip when it leaves its window.
private struct MenuTooltipAnchor: NSViewRepresentable {
    let tooltip: MenuTooltip

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onLeavingWindow = { [weak tooltip] in tooltip?.dismiss() }
        tooltip.anchor = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        tooltip.anchor = view
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        view.onLeavingWindow?()
    }

    final class AnchorView: NSView {
        var onLeavingWindow: (@MainActor () -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                onLeavingWindow?()
            }
        }

        // Never in the way of the pointer: clicks and hover belong to the element.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The one window every menu tooltip is shown in: borderless, never activating BatFi or
/// taking the pointer, and above the menu.
///
/// The window itself is clear and casts no shadow. The tooltip's background and shadow are
/// drawn inside it, with room around for the shadow, so the shadow fades and grows with the
/// rest: a window's own shadow would stand at full strength from the first frame.
@MainActor
private final class MenuTooltipPanel {
    static let shared = MenuTooltipPanel()

    /// The widest a tooltip grows before its text wraps, as the system's do.
    static let maxWidth: CGFloat = 300
    /// The room around the tooltip for its shadow.
    static let shadowMargin: CGFloat = 12
    /// Quick and without bounce: a tooltip is a glance, not an event.
    static let appearAnimation: Animation = .smooth(duration: 0.15)
    static let hideDuration: TimeInterval = 0.1

    /// Whose tooltip is on screen, if any.
    private(set) weak var owner: MenuTooltip?
    private let appearance = MenuTooltipAppearance()
    /// Measures the text; the panel's own view shows it.
    private let measure = NSHostingController(rootView: MenuTooltipLabel(text: ""))
    private lazy var panel = makePanel()
    /// Counts shows and hides, so a fade-out that a new show has overtaken neither orders
    /// the new tooltip out nor hides it, and a late fade-in does not revive a hidden one.
    private var generation = 0

    func show(_ text: String, for owner: MenuTooltip, below element: CGRect, within screen: CGRect) {
        generation += 1
        let generation = generation
        self.owner = owner
        measure.rootView = MenuTooltipLabel(text: text)
        let fitting = measure.sizeThatFits(in: CGSize(width: Self.maxWidth, height: .greatestFiniteMagnitude))
        let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
        let frame = MenuTooltipPlacement.frame(for: size, below: element, within: screen)
        appearance.text = text
        appearance.side = MenuTooltipPlacement.side(of: frame, from: element)
        panel.setFrame(frame.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin), display: true)
        // A new text for the tooltip on screen only takes its place.
        guard !appearance.isShown else { return }
        panel.orderFrontRegardless()
        // One turn of the main queue later, so the hidden state has been drawn to grow from.
        // A fade-out under way is picked up where it is.
        Task { [weak self] in
            guard let self, self.generation == generation else { return }
            withAnimation(Self.appearAnimation) {
                self.appearance.isShown = true
            }
        }
    }

    /// Hides the tooltip if it is still `owner`'s: one that has taken the panel over stays.
    /// Animated, it fades out and the panel is ordered out once it has; otherwise both at once.
    func hide(for owner: MenuTooltip, animated: Bool) {
        guard self.owner === owner else { return }
        self.owner = nil
        generation += 1
        let generation = generation
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                appearance.isShown = false
            }
            panel.orderOut(nil)
            return
        }
        withAnimation(.easeOut(duration: Self.hideDuration)) {
            appearance.isShown = false
        }
        // Ordered out on a clock rather than on the animation's completion, so the panel goes
        // even if the animation never reports back. A show since then keeps it.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hideDuration) + .milliseconds(50))
            guard let self, self.generation == generation else { return }
            self.panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let content = NSHostingView(rootView: MenuTooltipContent(appearance: appearance))
        // The panel's frame is set from the measured text; the view only fills it.
        content.sizingOptions = []
        panel.contentView = content
        return panel
    }
}

/// What the panel's view shows, and whether it is shown.
@MainActor
@Observable
private final class MenuTooltipAppearance {
    var text = ""
    var side: MenuTooltipPlacement.Side = .below
    var isShown = false
}

/// The tooltip as drawn in the panel: the text on the system's tooltip background, with a
/// shadow, all of which fades together.
///
/// Hidden, it sits a touch smaller and nudged towards its element, scaled from the edge
/// nearest it, so it grows out of the element as it fades in. With Reduce Motion it only
/// fades.
private struct MenuTooltipContent: View {
    let appearance: MenuTooltipAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cornerRadius: CGFloat = 6
    static let hiddenScale: CGFloat = 0.96
    static let hiddenSlide: CGFloat = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let isBelow = appearance.side == .below
        let moves = !reduceMotion && !appearance.isShown
        MenuTooltipLabel(text: appearance.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                MenuTooltipMaterial(cornerRadius: Self.cornerRadius)
            }
            .background {
                shadow(shape)
            }
            .scaleEffect(moves ? Self.hiddenScale : 1, anchor: isBelow ? .top : .bottom)
            .offset(y: moves ? (isBelow ? -Self.hiddenSlide : Self.hiddenSlide) : 0)
            .opacity(appearance.isShown ? 1 : 0)
            .padding(MenuTooltipPanel.shadowMargin)
            .accessibilityHidden(true)
    }

    /// The shadow alone, with the shape that casts it cut out: under the translucent
    /// background it would darken it.
    private func shadow(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(.black)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .mask {
                ZStack {
                    Rectangle()
                        .padding(-MenuTooltipPanel.shadowMargin)
                    shape
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
    }
}

/// The system's tooltip background, with rounded corners.
private struct MenuTooltipMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .toolTip
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = roundedMask
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// A stretchable rounded rectangle for the background's mask.
    private var roundedMask: NSImage {
        let radius = cornerRadius
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The tooltip's text, set like the system's: small, wrapping past the widest it grows.
private struct MenuTooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: NSFont.smallSystemFontSize))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            // The element itself says the same to VoiceOver.
            .accessibilityHidden(true)
    }
}
