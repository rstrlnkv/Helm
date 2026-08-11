// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

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
    /// It said something else. Kept for the log rather than mapped to «failed»:
    /// the set of things this tool can print is not ours to enumerate, and an
    /// unknown message is worth more in the trail than a word we chose.
    ///
    /// **Redacted at creation, so this case cannot hold a name.** The tool's
    /// sentence is usually *about* the configuration and therefore contains it —
    /// `cannot start Contoso Field Office: busy` — and this string is written
    /// straight into the diagnostic file, on the line that had already run the
    /// name through `Redact.vpn` to keep it out. Sanitising where the value is
    /// made rather than where it is printed is what makes that hold for the next
    /// reader too: the log line, and any screen that ever shows what the tool
    /// said.
    case refused(String)

    /// - Parameter name: the configuration the command was about, so its every
    ///   occurrence in the tool's answer can be replaced by the same tag the rest
    ///   of the module's log lines carry.
    public static func of(_ output: String, name: String) -> VPNCommandReply {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .accepted }
        // The tool's own wording, matched case-insensitively but not
        // translated: `scutil` is not localized, and a machine whose language
        // changed still prints this.
        //
        // Read *before* the name is taken out, because the name can look like the
        // wording: a configuration called «No» would otherwise turn `No service`
        // into a sentence this enum cannot classify at all.
        if text.lowercased().hasPrefix("no service") { return .noSuchService }
        return .refused(withoutTheName(text, name: name))
    }

    /// The name gone, case-insensitively — the tool has no reason to spell it the
    /// way the person did — and the result bounded. One log line is not the place
    /// for a wall of text: the file is 2 MB with a single rollover, so an
    /// unbounded message is everything else's trail pushed out of it.
    private static func withoutTheName(_ text: String, name: String) -> String {
        // An empty name is not a pattern. `replacingOccurrences` of "" is at best
        // a no-op, and the engine can be asked for one by a rule pointing at a
        // configuration that has since been renamed away.
        let named = name.isEmpty
            ? text
            : text.replacingOccurrences(of: name, with: Redact.vpn(name), options: [.caseInsensitive])
        return String(named.prefix(200))
    }
}
