import Foundation

/// The bridge between `DoctorParser`, which reads `brew doctor`'s text and
/// always answers `fix: nil`, and `DoctorFix.judge(_:installed:)`, which is the
/// only place allowed to answer `.runnable`. This file turns an issue's body
/// into a *candidate* argv and nothing more; it never decides that anything may
/// run.
///
/// ## What `brew doctor` actually prints
///
/// Measured on this Mac, Homebrew 7.0.1, 2026-09-15, whole answer on standard
/// error, exit 1. The two issues were a tap's `postflight` deprecation —
///
///     Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
///     Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
///       /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18
///
/// — and the deprecated formulae —
///
///     Warning: Some installed formulae are deprecated or disabled.
///     You should find replacements for the following formulae:
///
///       periphery
///
/// **Neither block prints a literal `brew …` command line**, and no block in
/// that run did. So there is no command in this text to lift out: the thing
/// that exists is a *heading* followed by an indented list of names, and the
/// act that answers it is Helm's reading of the heading, not brew's words.
/// That is why the mapping below is a hand-written list of headings rather than
/// a command scanner — a scanner would have nothing to scan, and would end up
/// inventing the command it claimed to have found.
///
/// ## What is deliberately not here
///
/// - **No command extraction.** A line of prose is not a command, a line naming
///   a path is not a command, and a backticked fragment inside a sentence is
///   not a command. Nothing in this file looks for one.
/// - **No title reading.** `argv(inBodyOf:)` takes the body `String`, so the
///   title is not in scope of the function at all — unreadable rather than
///   merely forbidden.
/// - **No judgement.** Every argv produced here goes to
///   `DoctorFix.judge(_:installed:)`, which owns the allowlist, the argument
///   counts and the spelling alphabet. This file does not re-check any of
///   those: a second copy of the alphabet is a second alphabet.
enum DoctorFixCandidate {

    /// Every heading `brew doctor` prints that Helm reads as proposing an act,
    /// and the act each one proposes. One entry today; `Heading.allCases` is
    /// named entry by entry in `OnlyANamedHeadingProposesAFixTests`, so a second
    /// cannot be added without its author being sent back here to read the
    /// checklist under ``argv(inBodyOf:)``.
    ///
    /// The raw value is matched against a whole body line by **exact equality**
    /// after trimming that line's outer whitespace, and nothing else: no case
    /// folding, no prefix, no substring. A heading brew re-spells in a later
    /// version is a heading Helm stops recognising, which costs a person one
    /// copied command and costs nobody a wrong act.
    enum Heading: String, CaseIterable, Sendable {

        /// Printed under «Some installed formulae are deprecated or disabled»,
        /// above an indented list of formula names.
        ///
        /// Brew's own sentence asks the person to *find replacements*; it names
        /// no command. `uninstall` is Helm's reading of that — the only act on
        /// `DoctorFix.Allowed` that touches a named formula, and the one the
        /// judge will refuse outright unless the name is on this Mac's own
        /// installed list.
        case deprecatedOrDisabledFormulae = "You should find replacements for the following formulae:"

        /// The subcommand this heading's items are operands of. `argv[0]`, in
        /// the shape `DoctorFix.judge(_:installed:)` expects — `brew` is not in
        /// it.
        var subcommand: String {
            switch self {
            case .deprecatedOrDisabledFormulae: return "uninstall"
            }
        }
    }

    /// The candidate command for one issue's body, or nil when there is none.
    ///
    /// nil is the answer for everything this file does not recognise, and it is
    /// the overwhelmingly common answer: of the two issues this Mac produces,
    /// one has no heading on the list and gets nil.
    ///
    /// The scan, in full:
    ///
    /// 1. Exactly one body line, trimmed, must equal exactly one `Heading`'s
    ///    raw value. Zero headings is nothing to act on; two is two acts and
    ///    nobody offered either.
    /// 2. From the line after it, every **indented** non-blank line is an item.
    ///    A blank line neither adds an item nor ends the list — brew separates
    ///    the heading from its list with one on this machine, and a blank line
    ///    that *ended* the list would take the first of two names and act on
    ///    it, which is the one failure worth being paranoid about here. An
    ///    unindented non-blank line, or the end of the body, ends the list.
    /// 3. Each item, trimmed, must be a single bare token: non-empty, no
    ///    interior whitespace. **A sentence is not an item** — the package name
    ///    a person reads inside a line of prose is prose, and «deprecated:
    ///    consider periphery's replacement» must not become
    ///    `brew uninstall consider`.
    /// 4. An item must not begin with `/`, `~` or `.`. **A path is not a
    ///    name** — a filesystem path is rooted and a Homebrew formula, cask or
    ///    tap name never is, so this is the one rule that separates the two
    ///    without guessing at what a path looks like. Brew prints paths on
    ///    indented lines of their own constantly (the `postflight` block above
    ///    is one), so this rule stands on its own and is not covered by the
    ///    heading gate.
    /// 5. **Exactly one item, or nothing.** `DoctorIssue.fix` is one optional
    ///    fix, so two names cannot both be carried; and beyond that, running
    ///    one of two names offered is not the act the person read, and running
    ///    both is a batch nobody sized. Two items therefore produce nil, as do
    ///    zero.
    ///
    /// ### Adding a second heading
    ///
    /// Before touching `Heading` or its test, answer all four in this file:
    ///
    /// 1. Paste the block `brew doctor` really printed, from a real run, into
    ///    the fixture in `OnlyANamedHeadingProposesAFixTests` — not a
    ///    reconstruction. Does the heading line appear exactly once, and is it
    ///    really a heading rather than the first sentence of a paragraph?
    /// 2. Are the items under it *names*, one per line, indented — or are they
    ///    paths, versions, or sentences? Rules 3 and 4 above are the whole
    ///    defence, and a heading whose items are anything else does not belong
    ///    on the list however tempting the act is.
    /// 3. Is the act you are mapping the heading to on `DoctorFix.Allowed`? If
    ///    it is not, this list is the wrong place to argue for it: the argument
    ///    belongs to the five questions under `DoctorFix.judge(_:installed:)`,
    ///    and an argv no entry admits is `.copyOnly` anyway.
    /// 4. Which live fact read off this Mac does the item get checked against
    ///    on the way through the judge? `uninstall`'s is the installed list. A
    ///    heading whose act has no such fact behind it produces an argv this
    ///    app may print and never run — decide that is what you want before
    ///    adding it, not afterwards.
    static func argv(inBodyOf body: String) -> [String]? {
        let lines = body.components(separatedBy: "\n")

        var found: (index: Int, heading: Heading)?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let heading = Heading(rawValue: trimmed) else { continue }
            guard found == nil else { return nil } // a second heading is a second act
            found = (index, heading)
        }
        guard let (headingIndex, heading) = found else { return nil }

        var items: [String] = []
        for line in lines.dropFirst(headingIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard line.first == " " || line.first == "\t" else { break }
            guard isABareName(trimmed) else { return nil }
            items.append(trimmed)
        }

        guard items.count == 1 else { return nil }
        return [heading.subcommand, items[0]]
    }

    /// One issue, with `fix` filled in from its own body and this Mac's
    /// installed list — the only place the two halves meet.
    ///
    /// The judge decides `.runnable` against `installed`; this function decides
    /// nothing except whether there is an argv to hand over. An issue whose body
    /// proposes nothing keeps `fix: nil`, which is a different thing from a fix
    /// that exists and may only be copied.
    static func judging(_ issue: DoctorIssue, installed: [String]) -> DoctorIssue {
        guard let argv = argv(inBodyOf: issue.body) else { return issue }
        return DoctorIssue(severity: issue.severity, title: issue.title, body: issue.body,
                           fix: DoctorFix.judge(argv, installed: installed))
    }

    /// Whether a trimmed body line is a bare name rather than prose or a path.
    /// Says only what rules 3 and 4 above say; the spelling alphabet is
    /// `DoctorFix`'s and is deliberately not repeated here.
    private static func isABareName(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains(where: \.isWhitespace) else { return false }
        return !trimmed.hasPrefix("/") && !trimmed.hasPrefix("~") && !trimmed.hasPrefix(".")
    }
}
