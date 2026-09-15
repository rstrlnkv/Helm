import Foundation

/// Parses `brew doctor`'s answer — printed entirely to standard error, one
/// tool run captured by `ProcessRunner.runCapturingDiagnostics` (its doc
/// comment carries the measurement: 1 byte of stdout against 1194 of stderr,
/// exit 1, this machine, 2026-09-14) — into the issues it names.
///
/// A block begins at a line starting `Warning:` or `Error:`; the rest of that
/// line is the title. The body absorbs every following line up to whichever
/// comes first: the next block, or a blank line followed by an unindented
/// line that is not itself a new block. That second boundary is how brew's
/// own aside to the reader — "Please note that these warnings are just used
/// to help…" — gets kept out of every issue's body: it showed up *between*
/// two blocks on this machine, not only after the last one, so the rule
/// cannot be "trim a trailing paragraph" and has to be a boundary the scan
/// itself refuses to cross. An indented line reached after a blank one (a
/// deprecated formula's name on its own line, say) is still body — the
/// indentation, not the blank line, is what tells the two apart.
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
        var starts: [(index: Int, severity: DoctorSeverity, title: String)] = []
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
            let bodyEnd = position + 1 < starts.count ? starts[position + 1].index : lines.count
            let bodyLines = Array(lines[(start.index + 1)..<bodyEnd])
            let issue = DoctorIssue(severity: start.severity, title: start.title,
                                     body: body(of: bodyLines), fix: nil)
            if !issues.contains(issue) {
                issues.append(issue)
            }
        }
        return issues
    }

    private static func title(of line: String, droppingPrefixCount count: Int) -> String {
        String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
    }

    /// Body lines are kept verbatim — no trimming of a line's own content —
    /// because a body line naming a path is somebody's path and this module
    /// does not re-spell it.
    private static func body(of lines: [String]) -> String {
        var kept: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.trimmingCharacters(in: .whitespaces).isEmpty else {
                kept.append(line)
                index += 1
                continue
            }
            // A blank line: whether it belongs to this body depends on what
            // comes after it, not on itself.
            guard index + 1 < lines.count else { break } // trailing blank
            let next = lines[index + 1]
            guard next.first == " " || next.first == "\t" else { break } // prose boundary
            kept.append(line)
            index += 1
        }
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.removeLast()
        }
        return kept.joined(separator: "\n")
    }
}
