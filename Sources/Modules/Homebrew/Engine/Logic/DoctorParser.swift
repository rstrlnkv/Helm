import Foundation

/// Parses `brew doctor`'s answer — printed entirely to standard error, one
/// tool run captured by `ProcessRunner.runCapturingDiagnostics` (its doc
/// comment carries the measurement: 1 byte of stdout against 1194 of stderr,
/// exit 1, this machine, 2026-09-14) — into the issues it names.
///
/// A block begins at a line starting `Warning:` or `Error:`. The title is **brew's
/// first sentence**, not its first physical line: brew hard-wraps its heredocs,
/// so `Homebrew's "sbin" was not found in your PATH but you have installed` is
/// where one break fell and «formulae that put executables in …» is the rest of
/// the same sentence. The title therefore takes following lines until one ends
/// with `.`, `!`, `?` or `:` — and never past a blank line, an indented line
/// (a list or a command), a Ruby backtrace frame, the next block or brew's
/// frame, so a title with no full stop cannot swallow the remediation or the
/// backtrace behind it. A sentence that ends inside a joined line (`builds to
/// fail. See:`) ends the title there; the rest of that line opens the body. The body is **the whole
/// rest of the block**: every following line up
/// to whichever comes first — the next block, or brew's own frame around the
/// findings (see `isFrame`). Blank lines inside a block are part of it, and so
/// is an unindented line after one: a finding is its text and then its
/// remediation, each free to hold a blank line (`Diagnostic::Finding#to_s`),
/// so `Unexpected dylibs:` with its files, the tools that exist at both PATH
/// entries and `Run `brew link` on these:` with its names all arrive as an
/// unindented line behind a blank one. An earlier rule ended the body there, and the very list
/// a person would act on never reached the screen.
///
/// The frame is what the scan refuses to cross: the aside to the reader —
/// "Please note that these warnings are just used to help…" — which
/// `cmd/doctor.rb` prints once, before its first warning, and the
/// support-tier message `brew doctor` prints on standard output after its last
/// finding, merged into the same capture and about the configuration, not about
/// that finding. The scan does not lean on where brew puts either: it stops at a
/// frame line wherever one lands, so a block is never given a trailing
/// paragraph that is not its own.
///
/// `brew` prints an identical block once per affected tap or cask in a single
/// run; those collapse to one issue, in first-seen order.
enum DoctorParser {
    /// nil for empty input — the tool said nothing at all, which this module
    /// must not read as "doctor ran and found a clean machine": that reading
    /// is exactly what a silently-refused query would also produce. An empty
    /// array is the honest answer for real output that named no
    /// `Warning:`/`Error:` line at all.
    static func parse(_ text: String) -> [DoctorIssue]? {
        guard !text.isEmpty else { return nil }

        let lines = text.components(separatedBy: "\n")
        var starts: [(index: Int, severity: DoctorSeverity, firstLine: String)] = []
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("Warning:") {
                starts.append((index, .caution, title(of: line, droppingPrefixCount: "Warning:".count)))
            } else if line.hasPrefix("Error:") {
                starts.append((index, .danger, title(of: line, droppingPrefixCount: "Error:".count)))
            }
        }
        guard !starts.isEmpty else { return [] }

        var issues: [DoctorIssue] = []
        for (position, start) in starts.enumerated() {
            let blockEnd = position + 1 < starts.count ? starts[position + 1].index : lines.count
            var title = start.firstLine
            var bodyStart = start.index + 1
            var spill: String?
            while bodyStart < blockEnd, !endsSentence(title), continuesSentence(lines[bodyStart]) {
                let line = lines[bodyStart].trimmingCharacters(in: .whitespaces)
                bodyStart += 1
                if let cut = sentenceEnd(in: line) {
                    title += " " + line[..<cut]
                    let rest = line[cut...].trimmingCharacters(in: .whitespaces)
                    spill = rest.isEmpty ? nil : rest
                    break
                }
                title += " " + line
            }
            var rest = Array(lines[bodyStart..<blockEnd])
            if let spill { rest.insert(spill, at: 0) }
            let issue = DoctorIssue(severity: start.severity, title: title,
                                     body: body(of: rest), fix: nil)
            if !issues.contains(issue) {
                issues.append(issue)
            }
        }
        return issues
    }

    private static func title(of line: String, droppingPrefixCount count: Int) -> String {
        String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
    }

    private static func endsSentence(_ title: String) -> Bool {
        guard let last = title.last else { return false }
        return ".!?:".contains(last)
    }

    /// Where the title's sentence ends inside a wrapped line that is not yet
    /// the end of the line: the index just past a `.`, `!`, `?` or `:` that is
    /// followed by a space and more text (`builds to fail. See:` — the title
    /// stops after `fail.`, and `See:` opens the body). nil when the line
    /// holds no such stop, in which case the whole line belongs to the title.
    private static func sentenceEnd(in line: String) -> String.Index? {
        var index = line.startIndex
        while index < line.endIndex {
            let next = line.index(after: index)
            if ".!?:".contains(line[index]), next < line.endIndex, line[next] == " " {
                return next
            }
            index = next
        }
        return nil
    }

    /// Whether a line is the wrapped rest of the title's sentence: text at the
    /// left margin that is neither blank, brew's frame nor a Ruby backtrace
    /// frame. An indented line is a list item or a command and starts the body.
    /// A message with no full stop — an exception's, which `brew.rb` prints as
    /// `Error: <message>` — is followed by its backtrace at the left margin, one
    /// `file.rb:line:in 'method'` frame per line; those are not its sentence.
    private static func continuesSentence(_ line: String) -> Bool {
        guard let first = line.first, !first.isWhitespace else { return false }
        return !isFrame(line) && !isBacktraceFrame(line)
    }

    private static func isBacktraceFrame(_ line: String) -> Bool {
        line.range(of: #"\.rb:\d+:in "#, options: .regularExpression) != nil
    }

    /// Body lines are kept verbatim — no trimming of a line's own content —
    /// because a body line naming a path is somebody's path and this module
    /// does not re-spell it. Only the blank lines at the end are dropped.
    private static func body(of lines: [String]) -> String {
        var kept = Array(lines.prefix { !isFrame($0) })
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.removeLast()
        }
        return kept.joined(separator: "\n")
    }

    /// The first line of what `brew doctor` prints around its findings rather
    /// than as one of them — `cmd/doctor.rb`'s aside to the reader, and
    /// `Finding.support_tier_message`, both spelled as brew spells them
    /// (`This is a Tier 2 configuration:`, `This is an Unsupported
    /// configuration:`). Matched at the start of an unindented line only, so a
    /// finding that quotes one of these sentences inside its own body is not cut.
    private static func isFrame(_ line: String) -> Bool {
        line.hasPrefix("Please note that these warnings are just used to help")
            || line.hasPrefix("This is a Tier ")
            || line.hasPrefix("This is an Unsupported configuration:")
    }
}
