//
//  DesktopStreamView.swift
//
//
//  A live feed of the display, playing where the helper pane's video plays.
//
//  The clip this pane plays is a recording of this pane, so it has to contain itself. The
//  magenta fill left a hole to composite one into afterwards; this removes the compositing
//  step altogether by pointing the pane at the screen it is on. The pane shows the display,
//  the display contains the pane, and the recursion is simply there — live, in one take,
//  with the window's rounded corners, its traffic-light buttons and the authorisation
//  sheet's vibrancy blur all real, because none of them is being reproduced.
//
//  Nothing is excluded from the capture. A filter that hid BatFi's own window would remove
//  the only thing worth filming.
//

import AVFoundation
import ScreenCaptureKit
import SwiftUI
import os

struct DesktopStreamView: NSViewRepresentable {
    func makeNSView(context: Context) -> DesktopStreamNSView {
        let view = DesktopStreamNSView()
        context.coordinator.start(rendering: view.displayLayer)
        return view
    }

    func updateNSView(_: DesktopStreamNSView, context _: Context) {}

    func makeCoordinator() -> DesktopStreamController {
        DesktopStreamController()
    }

    static func dismantleNSView(_: DesktopStreamNSView, coordinator: DesktopStreamController) {
        coordinator.stop()
    }
}

/// Backed by the display layer itself rather than hosting one, so the feed resizes with the
/// pane and needs no layout of its own.
final class DesktopStreamNSView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    init() {
        super.init(frame: .zero)
        // The same gravity `AVPlayerViewRepresented` uses. The rect is 4:3 and a display is
        // not, so the feed has to be cropped exactly as the finished clip will be — filming
        // against a different framing than the one the video ships in defeats the point.
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer = displayLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }
}

/// Starts the capture and feeds it to the layer.
///
/// `@unchecked Sendable` because ScreenCaptureKit delivers frames on its own queue: the two
/// stored properties are written once, before `startCapture` returns, and only read after.
final class DesktopStreamController: NSObject, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private let frameQueue = DispatchQueue(label: "software.micropixels.BatFi.desktop-stream")
    private let logger = Logger(subsystem: "software.micropixels.BatFi", category: "DesktopStream")

    @MainActor
    func start(rendering layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
        Task { await self.startCapture() }
    }

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            // The display the app is on. `first` would pick an arbitrary one on a multi-display
            // Mac, and filming the wrong screen is a take wasted rather than an error raised.
            let mainDisplayID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
                ?? content.displays.first
            else {
                logger.error("No display to capture")
                return
            }

            let configuration = SCStreamConfiguration()
            let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
            configuration.width = Int(Double(display.width) * scale)
            configuration.height = Int(Double(display.height) * scale)
            // 60fps. The feed is filmed rather than watched, and every dropped frame is a
            // stutter in a level of the recursion that cannot be fixed afterwards.
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 5
            configuration.showsCursor = true
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA

            // Nothing excluded. BatFi's own window in the capture is the entire subject.
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try await stream.startCapture()
            self.stream = stream
            logger.notice("Desktop stream started at \(configuration.width, privacy: .public)×\(configuration.height, privacy: .public)")
        } catch {
            // Almost always the Screen Recording permission, which is a one-time prompt and
            // has to be granted before filming rather than during it.
            logger.error("Desktop stream could not start: \(error, privacy: .public)")
        }
    }

    func stop() {
        let stream = stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }

    nonisolated func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        // Incomplete frames carry no new pixels — ScreenCaptureKit sends them for idle
        // regions — and enqueuing one blanks the layer.
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: rawStatus) == .complete
        else { return }

        guard let renderer = displayLayer?.sampleBufferRenderer else { return }
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
    }
}
