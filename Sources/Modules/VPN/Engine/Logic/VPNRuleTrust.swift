// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// Whether a per-app rule may act on the instance that is actually running.
///
/// **A bundle identifier is a claim, not an identity.** `RunningApps` reports
/// `CFBundleIdentifier`, which is a string in a plist any file can carry, and the
/// rules acted on it alone: a bundle anybody can build, carrying a mapped
/// identifier, raised a tunnel by launching and took it down by quitting. The
/// teardown was then booked as `.disconnected` — a rule doing as it was asked —
/// which also cleared the books that let the *later* real absence be reported as a
/// drop, so the person was not told either time.
///
/// The check happens at **launch** and the quit is refused by consequence:
/// `VPNAutoConnectCore` only undoes launches it recorded, and at quit time there
/// is no bundle left to read. That is also why a forged launch is not merely
/// ignored but leaves the identifier counted as running — a bundle that squats an
/// identifier can stop the *real* app's rule from firing, which is a nuisance in
/// the safe direction and not a way to move somebody's traffic.
///
/// A verdict rather than a `Bool`: the log line and the settings row each have to
/// say which refusal this was, and «the rule did nothing» with no reason is the
/// failure ARCHITECTURE.md § A rule that is being ignored is not a rule that is
/// quiet was written about.
public enum VPNRuleTrust {

    /// Exhaustive, and switched over without a `default` wherever it is read: a
    /// sixth answer must be a build error rather than something that quietly
    /// reads as «go ahead».
    public enum Verdict: String, Equatable, Sendable {
        /// The running instance is signed as the app the person picked.
        case act
        /// The rule predates identities. It refuses, and the row asks for the app
        /// to be chosen again — which records the identity and disturbs nothing
        /// else about the rule.
        case noIdentityRecorded
        /// The app the person picked carries no signature to bind to. Kept,
        /// because they asked for it, and inert, because an unsigned bundle's
        /// identity is one any other unsigned bundle can produce.
        case appNotSigned
        /// Something is running under that identifier and its signature could not
        /// be read. An id that cannot be verified is treated as no rule.
        case runningInstanceUnreadable
        /// It is signed, and as something else.
        case mismatch
    }

    /// - Parameter running: the identity of the instance carrying the rule's
    ///   bundle identifier, or nil when there is nothing to read. The two
    ///   rule-level verdicts do not depend on it, which is what lets the settings
    ///   page ask this same function with `nil`.
    public static func judge(rule: VPNAppRule, running: CodeIdentity?) -> Verdict {
        guard let recorded = rule.identity else { return .noIdentityRecorded }
        guard recorded.isVerifiable else { return .appNotSigned }
        guard let running, running.isVerifiable else { return .runningInstanceUnreadable }
        return running == recorded ? .act : .mismatch
    }
}
