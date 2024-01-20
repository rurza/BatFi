//
//  AVPlayerViewRepresented.swift
//  NepTunes
//
//  Created by Adam Różyński on 17/07/2021.
//

import AVKit
import Cocoa
import SwiftUI

struct AVPlayerViewRepresented: NSViewRepresentable {
    var player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = PlayerView()
        view.player = player
        return view
    }

    func updateNSView(_: AVPlayerView, context _: Context) {}
}

private class PlayerView: AVPlayerView {
    convenience init() {
        self.init(frame: .zero)
        autoresizingMask = [.height, .width]
        controlsStyle = .none
        videoGravity = .resizeAspectFill
        updatesNowPlayingInfoCenter = false
        allowsPictureInPicturePlayback = false
    }

    override open func scrollWheel(with _: NSEvent) {
        // Disable scrolling that can cause accidental video playback control (seek)
    }

    override open func keyDown(with event: NSEvent) {
        // Disable space key (do not pause video playback)

        let spaceBarKeyCode = UInt16(49)
        if event.keyCode == spaceBarKeyCode {
            return
        }
    }

    override open func hitTest(_: NSPoint) -> NSView? {
        return nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override var canBecomeKeyView: Bool {
        false
    }

    override func becomeFirstResponder() -> Bool {
        false
    }
}
