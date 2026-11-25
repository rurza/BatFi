//
//  ChargeRangeSlider.swift
//
//
//  The charge limit slider with sailing on: a second handle for the resume level, on one
//  20–100% track. SwiftUI has no two-handle slider, so this one is drawn to match the system
//  slider it replaces in the Charging pane — same frame, track, knob, tick marks and end
//  labels — so turning sailing on adds a handle rather than swapping in a different control.
//
//  The rules for how the handles push and stop each other live in `SailingRange`, which is
//  tested; this file only maps points to levels and back.
//

import AppShared
import L10n
import SwiftUI

struct ChargeRangeSlider: View {
    /// Written through the limit slider's rule: it shows the displayed limit and stores what
    /// the user picks, never clamping the stored value on its own.
    @Binding var limit: Int
    @Binding var resumeLevel: Int
    /// `ChargeLimitRange.lowestSelectable(for:)...100`: where the limit handle may go.
    let limitRange: ClosedRange<Int>
    /// The whole track, 20...100: both handles on one scale.
    let track: ClosedRange<Int>

    var body: some View {
        HStack(spacing: Metrics.labelSpacing) {
            Text(chargeLimitPercentageLabel(track.lowerBound))
                .modifier(EndLabelStyle())
            RangeTrack(limit: $limit, resumeLevel: $resumeLevel, limitRange: limitRange, track: track)
            Text(chargeLimitPercentageLabel(track.upperBound))
                .modifier(EndLabelStyle())
        }
        .accessibilityElement(children: .contain)
    }
}

/// The system slider's end labels: small and secondary since macOS 26, the pane's own text
/// before it; a step fainter while disabled, as the system's are.
private struct EndLabelStyle: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .font(.caption)
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .accessibilityHidden(true)
        } else {
            content
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .accessibilityHidden(true)
        }
    }
}

/// The two handles, as one name for each so drag, keyboard and VoiceOver share one code path.
private enum SailingHandle: Hashable {
    case resume
    case limit
}

/// The system slider's measurements, taken from renders of it in the Charging pane so the two
/// controls line up when the switch swaps one for the other.
private enum Metrics {
    /// The whole control, labels included, is this tall: the system slider's height.
    static let height: CGFloat = 18
    static let labelSpacing: CGFloat = 5

    static var knobSize: CGSize {
        if #available(macOS 26, *) {
            CGSize(width: 20, height: 16)
        } else {
            CGSize(width: 20, height: 20)
        }
    }

    static var trackHeight: CGFloat {
        if #available(macOS 26, *) { 6 } else { 4 }
    }

    /// Where the track's centre line sits from the top of the frame.
    static var trackCentre: CGFloat {
        if #available(macOS 26, *) { 8 } else { 9 }
    }

    static let tickSize: CGFloat = 2
    /// From the track's centre line down to the centre of a tick mark.
    static var tickDrop: CGFloat {
        if #available(macOS 26, *) { 5.25 } else { 6.5 }
    }
}

private struct RangeTrack: View {
    @Binding var limit: Int
    @Binding var resumeLevel: Int
    let limitRange: ClosedRange<Int>
    let track: ClosedRange<Int>

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlActiveState) private var controlActiveState

    /// The handle a drag moves, chosen once when it starts, and how far from that handle's
    /// centre it was grabbed, so the handle does not jump under the pointer.
    @State private var drag: (handle: SailingHandle, grabOffset: CGFloat)?

    var body: some View {
        GeometryReader { proxy in
            let scale = Scale(track: track, width: proxy.size.width)
            let resumeX = scale.x(for: resumeLevel)
            let limitX = scale.x(for: limit)

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: proxy.size.width, height: Metrics.trackHeight)
                    .offset(y: Metrics.trackCentre - Metrics.trackHeight / 2)

                Rectangle()
                    .fill(fillStyle)
                    .frame(width: max(0, limitX - resumeX), height: Metrics.trackHeight)
                    .offset(x: resumeX, y: Metrics.trackCentre - Metrics.trackHeight / 2)

                ticks(scale: scale)

                knob(.resume, x: resumeX)
                knob(.limit, x: limitX)
            }
            .frame(width: proxy.size.width, height: Metrics.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(scale: scale))
        }
        .frame(height: Metrics.height)
    }

    // MARK: - Drawing

    private var fillStyle: Color {
        if !isEnabled { return Color.primary.opacity(0.16) }
        return controlActiveState == .inactive ? Color.primary.opacity(0.23) : .accentColor
    }

    private func ticks(scale: Scale) -> some View {
        let levels = Array(stride(from: track.lowerBound, through: track.upperBound, by: SailingRange.step))
        return ForEach(levels, id: \.self) { level in
            Circle()
                .fill(Color.primary.opacity(isEnabled ? 0.26 : 0.1))
                .frame(width: Metrics.tickSize, height: Metrics.tickSize)
                .offset(
                    x: scale.x(for: level) - Metrics.tickSize / 2,
                    y: Metrics.trackCentre + Metrics.tickDrop - Metrics.tickSize / 2
                )
        }
        .accessibilityHidden(true)
    }

    private func knob(_ handle: SailingHandle, x: CGFloat) -> some View {
        let size = Metrics.knobSize
        return Capsule()
            .fill(Color.white)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 2, y: 0.5)
            .frame(width: size.width, height: size.height)
            .contentShape(.focusEffect, Capsule())
            // Focus the way the system slider takes it: by Tab when keyboard navigation is
            // on, never by a click, so dragging does not flash a focus ring.
            .focusable(interactions: .activate)
            .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in
                nudge(handle, by: -1)
                return .handled
            }
            .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in
                nudge(handle, by: 1)
                return .handled
            }
            // To VoiceOver each handle is a system slider — the slider role, its own name and
            // percentage, VO-arrow by a step — bound through `move`, so it clamps and pushes
            // the way dragging and the arrow keys do.
            .accessibilityRepresentation {
                Slider(value: accessibilityValue(of: handle), in: accessibilityRange(of: handle), step: Double(SailingRange.step)) {
                    Text(handle == .limit ? L10n.Sailing.limitHandleName : L10n.Sailing.resumeHandleName)
                }
                .accessibilityValue(chargeLimitPercentageLabel(handle == .limit ? limit : resumeLevel))
            }
            .offset(x: x - size.width / 2, y: Metrics.trackCentre - size.height / 2)
    }

    private func accessibilityValue(of handle: SailingHandle) -> Binding<Double> {
        Binding(
            get: { Double(handle == .limit ? limit : resumeLevel) },
            set: { move(handle, to: Int($0.rounded())) }
        )
    }

    /// Where each handle may go: the limit across its own range, the resume level from the
    /// floor up to the minimum gap under the limit.
    private func accessibilityRange(of handle: SailingHandle) -> ClosedRange<Double> {
        switch handle {
        case .limit:
            return Double(limitRange.lowerBound)...Double(limitRange.upperBound)
        case .resume:
            let lower = max(track.lowerBound, SailingRange.floor)
            return Double(lower)...Double(max(lower, limit - SailingRange.minimumGap))
        }
    }

    // MARK: - Input

    private func dragGesture(scale: Scale) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let current: (handle: SailingHandle, grabOffset: CGFloat)
                if let drag {
                    current = drag
                } else {
                    // The nearer handle; the two can overlap at the 5-point gap, and the
                    // midpoint between their centres splits them evenly.
                    let resumeX = scale.x(for: resumeLevel)
                    let limitX = scale.x(for: limit)
                    let start = value.startLocation.x
                    let handle: SailingHandle = start < (resumeX + limitX) / 2 ? .resume : .limit
                    let centre = handle == .limit ? limitX : resumeX
                    // Grabbed on the knob: keep the grab point under the pointer. On the bare
                    // track: the handle comes to the pointer, as the system slider's does.
                    let offset = abs(start - centre) <= Metrics.knobSize.width / 2 ? start - centre : 0
                    current = (handle, offset)
                    drag = current
                }
                move(current.handle, to: scale.level(at: value.location.x - current.grabOffset))
            }
            .onEnded { _ in drag = nil }
    }

    private func nudge(_ handle: SailingHandle, by steps: Int) {
        let from = handle == .limit ? limit : resumeLevel
        move(handle, to: from + steps * SailingRange.step)
    }

    /// Every input lands here, so dragging, the arrow keys and VoiceOver clamp the same way.
    /// Writes only what changed: a drag across one step's width writes once, not per point.
    private func move(_ handle: SailingHandle, to level: Int) {
        switch handle {
        case .limit:
            let clamped = min(max(level, limitRange.lowerBound), limitRange.upperBound)
            let levels = SailingRange.draggingLimit(to: clamped, resume: resumeLevel)
            // The resume level first: a limit lowered into it pushes it down, and written in
            // the other order the stored pair would be a limit on top of its resume level for
            // an instant — which the charging pass may read.
            if levels.resumeLevel != resumeLevel { resumeLevel = levels.resumeLevel }
            if levels.limit != limit { limit = levels.limit }
        case .resume:
            let resolved = SailingRange.draggingResume(to: level, limit: limit)
            if resolved != resumeLevel { resumeLevel = resolved }
        }
    }
}

/// Levels to points and back. The handles travel inside the track by half a knob at each end,
/// as the system slider's knob does, so a handle at 20% or 100% stays on the track.
private struct Scale {
    let track: ClosedRange<Int>
    let width: CGFloat

    private var inset: CGFloat { Metrics.knobSize.width / 2 }
    private var span: CGFloat { CGFloat(track.upperBound - track.lowerBound) }
    private var travel: CGFloat { max(1, width - inset * 2) }

    func x(for level: Int) -> CGFloat {
        inset + CGFloat(level - track.lowerBound) / span * travel
    }

    /// The level under `x`, snapped to the slider's 5-point steps and kept on the track.
    func level(at x: CGFloat) -> Int {
        let raw = Double(track.lowerBound) + Double((x - inset) / travel * span)
        let step = Double(SailingRange.step)
        let snapped = Int((raw / step).rounded()) * SailingRange.step
        return min(max(snapped, track.lowerBound), track.upperBound)
    }
}
