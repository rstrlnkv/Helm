// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What `scutil --nc start` and `--nc stop` said about themselves.
///
/// **The exit status is useless here and the output is the whole signal.**
/// Measured on macOS 27:
///
/// | command | output | exit |
/// |---|---|---|
/// | `--nc stop "NBCom VPN"` (a real service) | *empty* | 0 |
/// | `--nc start "no-such-vpn-name"` | `No service` | 0 |
/// | `--nc stop "no-such-vpn-name"` | `No service` | 0 |
///
/// So a command that did nothing at all reports success, and the one thing
/// that distinguishes it is a line on stdout — which both call sites threw
/// away (`_ = runner.run(args)`). A configuration renamed or deleted in System
/// Settings, or a rule pointing at one, failed in complete silence: no log
/// line, nothing on screen, and a tunnel that simply never came up.
///
/// The sibling path had already learned this. `UnreadableListTests` exists
/// because `--nc list` answering nothing looked exactly like a Mac with no VPN
/// configured; its own comment says «`ScutilRunner.run` returns only the tool's
/// stdout and throws the exit status away». The list was fixed and the two
/// commands were not.
public enum VPNCommandReply: Equatable, Sendable {
    /// `scutil` said nothing, which is what it says when it did the thing.
    case accepted
    /// There is no configuration by that name — renamed, deleted, or a rule
    /// pointing at one that is gone.
    case noSuchService
    /// It said something else. Kept verbatim for the log rather than mapped to
    /// a case: the set of things this tool can print is not ours to enumerate,
    /// and an unknown message is worth more in the trail than «failed».
    case refused(String)

    public static func of(_ output: String) -> VPNCommandReply {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .accepted }
        // The tool's own wording, matched case-insensitively but not
        // translated: `scutil` is not localized, and a machine whose language
        // changed still prints this.
        if text.lowercased().hasPrefix("no service") { return .noSuchService }
        return .refused(text)
    }

    public var isAccepted: Bool { self == .accepted }
}
