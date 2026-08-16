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

    /// Read once. This is consulted from a view body, and `ProcessInfo.arguments` rebuilds the
    /// array on every access.
    static let isEnabled: Bool = ProcessInfo.processInfo.arguments.contains(launchArgument)

    /// Magenta rather than green. The app's own brand colour is green, and a fill that also
    /// occurs in the UI is one the compositing step cannot tell apart from the pixels it is
    /// meant to leave alone.
    static let fillColor = Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)

}
