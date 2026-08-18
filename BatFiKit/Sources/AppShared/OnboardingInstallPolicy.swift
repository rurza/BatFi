//
//  OnboardingInstallPolicy.swift
//  BatFi
//
//  What the onboarding helper pane should say while it waits for a registration to land.
//
//  Onboarding watches `SMAppService.status` in a loop and, until this existed, understood
//  exactly two readings: `.enabled` (finish) and `.notRegistered` (install once). Every other
//  reading fell through to "keep waiting" — including `.requiresApproval`, the one reading
//  that means macOS is waiting for the *user* and will never move on its own. The pane spun
//  its button forever and said nothing.
//
//  Pure, because the rule that matters most here is which of two simultaneously-true things
//  to say, and that is a decision rather than an I/O result.
//

import Foundation

/// What the pane knows about an install that has not finished.
public enum OnboardingInstallProgress: Sendable, Equatable {
    /// Nothing worth saying yet. The button stays busy.
    case waiting
    /// macOS holds the registration and wants the user's consent in Login Items.
    case needsApproval
    /// The record is approved and macOS is refusing it anyway. Only the user can clear it,
    /// and only by turning the item off and back on.
    case needsManualReset
    /// macOS refused the registration outright. Carries the reason it gave.
    case failed(String)

    /// Whether the pane is still doing something. Drives the button's spinner.
    ///
    /// Both of the other cases are places where the app has stopped and is waiting on a
    /// person. A spinner there claims work that is not happening.
    public var isBusy: Bool {
        self == .waiting
    }
}

public enum OnboardingInstallPolicy: Sendable {
    /// Status ticks a refusal must survive before it is announced. The stream ticks every
    /// 1.5s, so this is about thirty seconds.
    public static let failureGraceTicks = 20

    /// Status ticks a pending approval must survive before the pane says anything. About
    /// fifteen seconds against the same 1.5s stream.
    ///
    /// Registering posts macOS's own consent prompt — "BatFi.app can run in the background
    /// for all users. Do you want to allow this?" — and `SMAppService.status` reports
    /// `.requiresApproval` from the moment the registration lands, which is *before* anyone
    /// has had a chance to answer it. Measured at 0.6s after `register()`. Announcing there
    /// puts a modal over the pane to recommend the long way round — open System Settings,
    /// find BatFi in a list, turn it on — while the one-click Allow is still on screen.
    ///
    /// Long enough for a person to read a notification and click a button; short enough that
    /// someone who dismissed it is not left watching a spinner. The System Settings route is
    /// still the only one that works for a prompt that has been missed, so nothing is lost by
    /// saying it late, and it stays said for every later tick.
    public static let approvalGraceTicks = 10

    /// One arm per reading, exhaustively — a missing arm is the whole bug this replaces.
    ///
    /// - Parameter registrationError: what `register()` threw, if it threw. Not a verdict on
    ///   its own: it can be overtaken by a record that lands a tick later, which is exactly
    ///   what "Operation not permitted" followed by `.requiresApproval` was.
    /// - Parameter tick: how many status readings this attempt has seen, from zero.
    public static func progress(
        status: HelperServiceStatus,
        registrationError: String?,
        tick: Int
    ) -> OnboardingInstallProgress {
        switch status {
        // Two different situations arrive here as one value. macOS folds "waiting for your
        // consent" and "you consented and I am refusing anyway" into `.requiresApproval`;
        // `smd` distinguishes them with a disposition flag the public enum has no room for:
        //
        //     disposition=[enabled, disallowed, notified], have LWCR=true   →   status: 2
        //
        // `enabled` is the user's own switch, already on. So the refusal is the only signal
        // left, and only once it has outlived the grace — a lone EPERM here is the ordinary
        // transient refusal, and a transient one is gone before the grace is up.
        case .requiresApproval:
            // The prompt macOS raised on registration is still up and unanswered. It offers
            // exactly what this pane would ask for, in one click.
            guard tick >= approvalGraceTicks else { return .waiting }
            guard registrationError != nil, tick >= failureGraceTicks else { return .needsApproval }
            return .needsManualReset
        // A record exists. Whether a helper answers is a different question, and the ping and
        // ownership checks own it.
        case .enabled:
            return .waiting
        // The same absence, either way: `.notFound` is a record naming a bundle that is gone.
        case .notRegistered, .notFound:
            guard let registrationError, tick >= failureGraceTicks else { return .waiting }
            return .failed(registrationError)
        }
    }
}
