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
    /// - Parameter knownNames: every configuration this Mac has. **The tool's
    ///   explanation is often about a different one** — the configuration already
    ///   holding the interface, the one whose gateway answered — and one name in
    ///   the diagnostic file is the whole of what redaction exists to prevent.
    ///   Defaulted to nothing so a caller that has no list still gets the name it
    ///   asked about taken out; the engine passes the list it has just read.
    public static func of(_ result: HelmProcess.Result, name: String,
                          knownNames: [String] = []) -> VPNCommandReply {
        // **A tool that never ran is not a tool that agreed.** The table above
        // is about `scutil`'s own answers, all of which arrive with status 0 —
        // but a spawn that fails answers nothing at all, and that used to be
        // the same empty string as a connect it had performed. `HelmProcess`
        // reports a non-zero status for exactly that case, so it is read first
        // and separately: silence is only consent when the tool was there to
        // give it.
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = [name] + knownNames
        guard result.status == 0 else {
            return .refused(text.isEmpty ? "scutil did not run (status \(result.status))"
                                         : withoutTheNames(text, names: names))
        }
        guard !text.isEmpty else { return .accepted }
        // The tool's own wording, matched case-insensitively but not
        // translated: `scutil` is not localized, and a machine whose language
        // changed still prints this.
        //
        // Read *before* the name is taken out, because the name can look like the
        // wording: a configuration called «No» would otherwise turn `No service`
        // into a sentence this enum cannot classify at all.
        if text.lowercased().hasPrefix("no service") { return .noSuchService }
        return .refused(withoutTheNames(text, names: names))
    }

    /// Every name gone, case-insensitively — the tool has no reason to spell one
    /// the way the person did — and the result bounded. One log line is not the
    /// place for a wall of text: the file is 2 MB with a single rollover, so an
    /// unbounded message is everything else's trail pushed out of it.
    ///
    /// **Longest first**, or a name that contains another leaves half of itself
    /// standing beside the shorter one's tag: «Office VPN Backup» swept for
    /// «Office» first reads `vpn#1a2b VPN Backup`, which names the configuration
    /// as plainly as printing it would.
    ///
    /// **Not `.literal`.** Foundation's non-literal search compares canonically,
    /// so a name the tool prints decomposed is found by a rule that stored it
    /// precomposed and the other way round — `scutil` reads the name out of the
    /// network configuration store and the rule was written into a text field, so
    /// the two spellings differ byte for byte while naming one configuration.
    /// That property is Foundation's rather than this function's, which is why
    /// `ARefusalNamesNoConfigurationTests` pins it: adding `.literal` for speed
    /// would put the name back in the file with nothing to say so.
    private static func withoutTheNames(_ text: String, names: [String]) -> String {
        // An empty name is not a pattern. `replacingOccurrences` of "" is at best
        // a no-op, and the engine can be asked for one by a rule pointing at a
        // configuration that has since been renamed away.
        var swept = text
        for name in Set(names.filter { !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            swept = swept.replacingOccurrences(of: name, with: Redact.vpn(name),
                                               options: [.caseInsensitive])
        }
        return String(swept.prefix(200))
    }
}
