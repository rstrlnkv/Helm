import Foundation

/// A command line `brew doctor` printed, and whether Helm may run it.
///
/// `DoctorParser` produces every issue with `fix: nil`: parsing text is not
/// judging a command safe to run. `DoctorFix.judge(_:installed:)` is the only
/// place in this module that may answer `.runnable`.
public struct DoctorFix: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Safe for Helm to run through the module's own operation path.
        case runnable
        /// Shown to the person to copy; never executed by this app.
        case copyOnly
    }
    public let argv: [String]
    public let kind: Kind
    init(argv: [String], kind: Kind) {
        self.argv = argv
        self.kind = kind
    }
}

extension DoctorFix {

    /// The allowlist: every command this app may ever run on a person's behalf
    /// because `brew doctor` suggested it. Named in
    /// `OnlyAnAllowedFixMayBeRunTests`, so a second entry sends its author back
    /// to the checklist under `judge(_:installed:)`.
    ///
    /// Three a reader will expect and that are **deliberately** absent:
    ///
    /// - `cleanup` — no `brew doctor` heading Helm parses suggests it, so no
    ///   page offers it; an entry nothing reaches is an entry nobody reads.
    ///
    /// - `update-reset` — it discards local taps, which are somebody's work
    ///   and are not recoverable from anything Helm holds.
    /// - `untap` — it takes everything installed from that tap with it, so the
    ///   visible act (one tap goes away) is not the act performed.
    enum Allowed: CaseIterable, Sendable {

        /// `["uninstall", <name>]` where `<name>` is in the installed list the
        /// judge was handed. The name comes out of prose, so it is checked
        /// against what this Mac actually has. Exactly one name: a second
        /// name is a second act, and nobody offered it.
        case uninstallAnInstalledPackage

        /// Whether this entry admits `argv`. Argument-exact in both directions:
        /// the count is part of the match, so nothing is accepted by a prefix.
        func admits(_ argv: [String], installed: [String]) -> Bool {
            switch self {
            case .uninstallAnInstalledPackage:
                return argv.count == 2 && argv[0] == "uninstall" && installed.contains(argv[1])
            }
        }
    }

    /// Judges one command `brew doctor` printed against the allowlist above.
    ///
    /// **What `argv` is.** The subcommand and its operands: `brew` is *not*
    /// argv[0], and `--` is not in it (the runner adds it). An argv that still
    /// carries `brew` is `.copyOnly`: removing it would be a normalisation.
    ///
    /// **No normalisation, at all.** No case folding, no trimming, no
    /// re-splitting on whitespace. Every normalisation judges one string and
    /// runs another; `UNINSTALL` or `" uninstall "` is simply not recognised,
    /// which costs a person one copied line.
    ///
    /// **The character rule.** Before the allowlist is consulted, every element
    /// must be non-empty, must not begin with `-` (brew reads that as an
    /// option, not as the name it stands in for), and must be spelled only from
    /// the alphabet a Homebrew name and subcommand use — letters, digits and
    /// ``.``, `_`, `-`, `+`, `@`, `/`. That alphabet holds no quote, dollar,
    /// backtick, semicolon, ampersand, parenthesis, backslash, space or
    /// newline, so a shell metacharacter is unrepresentable rather than
    /// unlikely. The installed list is itself parsed out of another tool's
    /// output: being in it is not proof that a string is a name.
    ///
    /// **Adding a second entry.** It has to answer all five, in the file, before
    /// the test above is changed:
    ///
    /// 1. What does it do that nothing already on the list does, and is that
    ///    worth a button that acts?
    /// 2. What is lost if it runs when it should not have — and can the person
    ///    get it back? `update-reset` and `untap` are off the list on this one
    ///    alone.
    /// 3. Which of its parts came out of `brew doctor`'s prose, and what live
    ///    fact read off this Mac is each of those parts checked against? A part
    ///    with no such fact behind it is not admissible.
    /// 4. Is it argument-exact, counting arguments, so no argument can be
    ///    carried along beside the ones matched?
    /// 5. Does every element it admits fit the alphabet above — and if it needs
    ///    a wider one, what does the widened alphabet let through everywhere
    ///    else on this list?
    static func judge(_ argv: [String], installed: [String]) -> DoctorFix {
        guard argv.allSatisfy(isSpellable) else {
            return DoctorFix(argv: argv, kind: .copyOnly)
        }
        let admitted = Allowed.allCases.contains { $0.admits(argv, installed: installed) }
        return DoctorFix(argv: argv, kind: admitted ? .runnable : .copyOnly)
    }

    /// The alphabet a Homebrew subcommand, formula, cask or tap name is spelled
    /// from — `python@3.12` and `sozercan/homebrew-repo` are both in it. Stated
    /// as what is allowed rather than as what is forbidden, so a character
    /// nobody thought of is refused by default.
    private static let spellable = Set("abcdefghijklmnopqrstuvwxyz"
        + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+@/")

    private static func isSpellable(_ element: String) -> Bool {
        guard !element.isEmpty, !element.hasPrefix("-") else { return false }
        return element.allSatisfy(spellable.contains)
    }
}
