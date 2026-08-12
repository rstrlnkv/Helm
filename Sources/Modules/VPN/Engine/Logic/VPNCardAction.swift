// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The one verb a connection card offers, and whether it can be pressed.
///
/// Here rather than in the view for the reason `VPNStatus.isUp` is here: which
/// statuses can be acted on is the engine's vocabulary, and a view that answers
/// it for itself is a view that can answer it differently. It did — the card
/// disabled its button for *every* transition, including the one the engine can
/// act on, under a comment saying the opposite.
public struct VPNCardAction: Equatable, Sendable {
    /// Which way the request goes — `VPNVerb`, the module's own, not a nested
    /// copy of it. Not a `Bool`: the card draws two different buttons, one of
    /// them prominent, and «up» is not the same question.
    public let verb: VPNVerb
    public let enabled: Bool

    public init(verb: VPNVerb, enabled: Bool) {
        self.verb = verb
        self.enabled = enabled
    }

    public static func of(_ status: VPNStatus) -> VPNCardAction {
        switch status {
        // **Including `.connecting`, which is the whole point.** `scutil --nc
        // stop` acts on a service that is still coming up, and a tunnel waiting
        // on a server that never answers is exactly when somebody wants out —
        // the card used to offer them a greyed-out button and System Settings.
        case .connected, .connecting:
            return VPNCardAction(verb: .disconnect, enabled: true)
        // Going down, and there is nothing to ask for until it has. Whether
        // `--nc start` is accepted here has not been measured, and this state
        // ends by itself in seconds where `connecting` can hang for good.
        case .disconnecting:
            return VPNCardAction(verb: .connect, enabled: false)
        case .disconnected, .unknown:
            return VPNCardAction(verb: .connect, enabled: true)
        }
    }
}
