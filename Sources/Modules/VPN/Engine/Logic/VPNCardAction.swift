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
    /// Which of three words the control draws.
    ///
    /// Three, where `VPNVerb` has two — and that is the point of it being its
    /// own type rather than a third case of the verb. `--nc stop` is one
    /// command whether it is cancelling a handshake or bringing a tunnel down,
    /// and `VPNVerb` is what the tool is asked and what the log and a refusal
    /// are spelled from; a third direction there would be a command that does
    /// not exist and a refusal sentence nothing can produce.
    ///
    /// **Asking one word to mean both was wrong in two languages outright.**
    /// 接続解除 is *release the connection* and 断开连接 is *break the
    /// connection*, and a handshake has no connection yet to release or break.
    public enum Word: String, Equatable, Sendable {
        case connect, disconnect, cancel
    }

    public let word: Word
    public let enabled: Bool

    /// Which way the request goes — `VPNVerb`, the module's own, not a nested
    /// copy of it. Derived rather than stored beside the word, so «Cancel» and
    /// «Disconnect» cannot come to mean two different commands: they are one
    /// `--nc stop` seen from either end of a handshake.
    public var verb: VPNVerb {
        switch word {
        case .connect: return .connect
        case .disconnect, .cancel: return .disconnect
        }
    }

    public init(word: Word, enabled: Bool) {
        self.word = word
        self.enabled = enabled
    }

    public static func of(_ status: VPNStatus) -> VPNCardAction {
        switch status {
        case .connected:
            return VPNCardAction(word: .disconnect, enabled: true)
        // **Acted on, which is the whole point.** `scutil --nc stop` acts on a
        // service that is still coming up, and a tunnel waiting on a server
        // that never answers is exactly when somebody wants out — the card used
        // to offer them a greyed-out button and System Settings. The word is
        // its own, because what is being abandoned is the handshake.
        case .connecting:
            return VPNCardAction(word: .cancel, enabled: true)
        // Going down, and there is nothing to ask for until it has. Whether
        // `--nc start` is accepted here has not been measured, and this state
        // ends by itself in seconds where `connecting` can hang for good.
        //
        // **The dimmed control keeps the word that was pressed.** It read a
        // disabled «Connect», so the control under the cursor turned into the
        // thing nobody had asked for at the moment it stopped answering.
        case .disconnecting:
            return VPNCardAction(word: .disconnect, enabled: false)
        case .disconnected, .unknown:
            return VPNCardAction(word: .connect, enabled: true)
        }
    }
}
