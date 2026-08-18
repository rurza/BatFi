//
//  OnboardingRecordingMode.swift
//
//
//  Created by Adam on 16/08/2026.
//

import Foundation
import SwiftUI

/// Replaces the helper pane's video with a flat fill, so a screen recording of that pane can
/// have the finished video composited back into the rect afterwards.
///
/// The helper pane and nothing else. The licence and charging panes share the same player but
/// keep their own clips, because they are not what is being re-recorded and a stand-in there
/// would only put a hole in footage nobody is filming.
///
/// The clip the helper pane plays is itself a recording of the helper pane, and there is no way
/// to film that without leaving a hole to put it in — the video has to contain itself. Filming
/// the pane while it plays the *previous* version of the clip would show the wrong app: the
/// order of the panes changed, so the old clip no longer depicts what is on screen.
///
/// Gated on a launch argument rather than `#if DEBUG` on purpose. The helper install has to be
/// real on camera — the notification and the authorisation sheet are the subject — and that
/// means a signed Release build, which rules out a compile-time flag. Pass it with:
///
///     open -a BatFi.app --args --record-onboarding
enum OnboardingRecordingMode {
    static let launchArgument = "--record-onboarding"

    /// Plays a file from disk in the helper pane instead of the clip it ships with:
    ///
    ///     open -a BatFi.app --args --onboarding-video /tmp/helper_pass1.mov
    ///
    /// This is the compositing step, done in camera. The clip has to contain itself, and the
    /// alternative is a post-production composite of a rectangle into a rectangle, repeated
    /// for every level of recursion — with the window's rounded corners, its traffic lights
    /// and the authorisation sheet's translucency all faked at each one. Playing the previous
    /// pass back inside the real pane gets every one of those for nothing, because they are
    /// not being reproduced: they are simply happening.
    ///
    /// Film a pass, export it, point this at the export, film again. Each pass buries the
    /// magenta one level deeper; three or four passes and it is smaller than a pixel.
    ///
    /// The app is not sandboxed, so any readable path works — but `~/Desktop`, `~/Documents`
    /// and `~/Downloads` are TCC-protected, and the consent dialog would land in the middle
    /// of a take. `/tmp` and `~/Movies` are not. If the file must live on the Desktop, launch
    /// once and grant access before recording anything.
    static let videoArgument = "--onboarding-video"

    /// Read once. This is consulted from a view body, and `ProcessInfo.arguments` rebuilds the
    /// array on every access.
    static let isEnabled: Bool = ProcessInfo.processInfo.arguments.contains(launchArgument)

    /// The file to play in the helper pane, if one was given and exists.
    ///
    /// Nil for a path that is missing or unreadable, rather than an `AVPlayerItem` that fails
    /// silently — a black rectangle and a pane playing its shipped clip look the same on a
    /// monitor, and the difference is only discovered after the take.
    static let localVideoURL: URL? = {
        guard let path = videoPath(from: ProcessInfo.processInfo.arguments) else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.isReadableFile(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }()

    /// Whether the pane stands a flat fill in for its video.
    ///
    /// The fill is for the first pass, when there is nothing yet to play, and for a path that
    /// could not be read. That second case matters more than it looks: falling back to the
    /// shipped clip would put the *old* helper video in the rect, which is a plausible-looking
    /// picture of the wrong app, and the mistake would be found after the take rather than
    /// before it. Magenta is found immediately.
    static var showsFill: Bool {
        guard localVideoURL == nil else { return false }
        return isEnabled || videoPath(from: ProcessInfo.processInfo.arguments) != nil
    }

    /// Separated from the `ProcessInfo` read so the parsing can be reasoned about on its own:
    /// the argument may be absent, last with nothing after it, or followed by another flag.
    static func videoPath(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: videoArgument) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        guard !value.hasPrefix("--") else { return nil }
        return value
    }

    /// Magenta rather than green. The app's own brand colour is green, and a fill that also
    /// occurs in the UI is one the compositing step cannot tell apart from the pixels it is
    /// meant to leave alone.
    static let fillColor = Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
}
