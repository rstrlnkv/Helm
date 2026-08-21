import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// `PrivateFile` answers whether the write landed, and a caller that drops that
/// answer has turned a refusal into a success.
///
/// The house already carries this rule pointed at three other ports — `pmset`
/// that would not take the setting, `launchctl` that would not load, a removal
/// that got no answer — and it had not reached the filesystem. Eight call sites
/// dropped the `Bool`: the tree Disk reopens on, the salt the log's tags are
/// derived from, the note that says an update is in flight, the journal a
/// background scan compares against, the digest cache that is the whole prize of
/// a Duplicates sweep, a marker, and the log itself twice.
///
/// **What made it survive is that the two spellings look the same.**
/// `PrivateFile.write(x, to: y)` and `_ = PrivateFile.write(x, to: y)` differ by
/// four characters, and until this scan existed nothing — not the compiler,
/// which was told `@discardableResult`, and not a reader — could tell a decision
/// from an oversight. So the rule is not "use the result": it is **decide out
/// loud**. Use it, or discard it with `_ =` and say beside it why the refusal
/// does not matter here.
///
/// It is a source scan and not a type-system rule because Swift has no way to
/// say "discardable, but only where somebody wrote down that it is".
final class ARefusalFromTheDiskIsNotASuccessTests: XCTestCase {

    private static let privateFile = "Sources/HelmRuntime/PrivateFile.swift"

    /// The entry points that answer, read out of the file itself.
    ///
    /// **Not a list typed here.** A hand-written list of names is tied to what
    /// it names or it is a comment, and this one would have gone stale on its
    /// first day: `writeMakingTheFolder` was added while this very change was
    /// being made, and a spelled-out `["write", "directory", "harden"]` would
    /// have let every call to it drop its answer with the guard still green.
    /// Read from the declarations instead, so a new way to refuse is covered by
    /// the scan the moment it exists.
    private func answering() throws -> Set<String> {
        var names: Set<String> = []
        for statement in try statements(of: Self.privateFile) {
            guard statement.text.contains("-> Bool"),
                  let range = statement.text.range(of: "public static func ") else { continue }
            let rest = statement.text[range.upperBound...]
            names.insert(String(rest.prefix { $0.isLetter || $0.isNumber }))
        }
        return names
    }

    // MARK: - Reading Swift as statements rather than as lines

    /// A statement, however many lines it was written across.
    ///
    /// **The first version of this scan read one line at a time and reported
    /// seven correct call sites as defects** — a `guard` whose condition
    /// continues on the next line, an `&&` whose left half ends one, a
    /// single-expression function body. Every one of those *uses* the answer;
    /// none of them has the use on the same line as the call. A line is not a
    /// statement, and a check that cannot tell the difference reports the
    /// careful sites and would be switched off within a week.
    private struct Statement {
        /// The line the statement opens on, which is what a finding must name.
        let line: Int
        let text: String
        /// The statement above this one, already folded.
        let previous: String
        /// The next line with anything on it, for spotting a body that closes
        /// immediately after its one expression.
        let next: String
    }

    /// A line that cannot stand alone: it continues the one above it.
    private static let opensAsContinuation = ["&&", "||", "?", ":", "+", "."]
    /// A line that cannot end a statement: the one below it continues this.
    private static let endsExpectingMore = [",", "&&", "||", "=", "(", "->", "?", ":", "+"]

    private func statements(of file: String) throws -> [Statement] {
        let code = try RepoSource.lines(of: file).map {
            RepoSource.code($0).trimmingCharacters(in: .whitespaces)
        }
        var folded: [(line: Int, text: String)] = []
        for (index, line) in code.enumerated() where !line.isEmpty {
            let continues = Self.opensAsContinuation.contains { line.hasPrefix($0) }
                || (folded.last.map { last in
                    Self.endsExpectingMore.contains { last.text.hasSuffix($0) }
                } ?? false)
            if continues, let last = folded.popLast() {
                folded.append((last.line, last.text + " " + line))
            } else {
                folded.append((index + 1, line))
            }
        }
        return folded.enumerated().map { position, statement in
            Statement(line: statement.line,
                      text: statement.text,
                      previous: position > 0 ? folded[position - 1].text : "",
                      next: position + 1 < folded.count ? folded[position + 1].text : "")
        }
    }

    private struct Site {
        let file: String
        let line: Int
        let text: String
        /// Everything in the statement before the call.
        let before: String
        let statement: Statement

        var location: String { "\(file):\(line)" }
    }

    /// Every `PrivateFile.<answering>(…)` in `Sources`, as statements.
    private func sites() throws -> [Site] {
        var found: [Site] = []
        let answering = try self.answering()
        for file in try RepoSource.swiftFiles(under: "Sources") {
            for statement in try statements(of: file) {
                for name in answering {
                    guard let range = statement.text.range(of: "PrivateFile.\(name)(")
                    else { continue }
                    found.append(Site(
                        file: file,
                        line: statement.line,
                        text: statement.text,
                        before: String(statement.text[statement.text.startIndex..<range.lowerBound])
                            .trimmingCharacters(in: .whitespaces),
                        statement: statement))
                }
            }
        }
        return found
    }

    /// The call stands alone — nothing in its statement consumes what it
    /// answered.
    ///
    /// Everything in front of the call inside one statement — `=`, `return`,
    /// `guard`, `if !`, a `,`, an `&&` — is something taking the value. What is
    /// left is the two ways a statement can open: at the start of a line, and
    /// straight after a brace or a closure's `in`.
    ///
    /// **An implicit return is read as a drop, on purpose.** Swift lets a body
    /// of one expression *be* the return, and nothing short of a type-checker
    /// can tell `{ PrivateFile.write(x, to: y) }` handing back a `Bool` from the
    /// same four words throwing one away — the two are the same characters and
    /// differ only in what encloses them. Guessing from a `->` on the brace goes
    /// wrong in both directions: it waves through the first statement of
    /// several, and it cannot see a closure, which returns with no `->`
    /// anywhere. So the four sites that relied on it say `return` now. Six
    /// characters, at the exact places where whether the answer travels is the
    /// whole question.
    private func dropsTheAnswer(_ site: Site) -> Bool {
        if site.before.isEmpty { return true }
        if site.before.hasSuffix("{") { return true }
        // A closure's own body starts after `in`, and that is a statement. As a
        // whole word, so `begin` and `within` are not read as one.
        return site.before.split(whereSeparator: { " \t(){},".contains($0) }).last == "in"
    }

    // MARK: - The rule

    /// The scan can only mean something while the compiler stays quiet, and it
    /// stays quiet for exactly one reason.
    ///
    /// `@discardableResult` on these three is what made every dropped call
    /// legal, and re-adding it would take the second signal away — the warning
    /// at the call site, which arrives while somebody is typing rather than when
    /// the suite runs. Asserted here so putting it back is a decision somebody
    /// makes against a failing test, never an afternoon's convenience.
    func testTheFileStillAsksItsCallersToDecide() throws {
        // Read as code, not as text. The file explains this rule in a comment
        // that has to spell the attribute out, and a scan reading its own
        // explanation as the offence is how these checks get switched off.
        let code = try RepoSource.lines(of: Self.privateFile)
            .map(RepoSource.code).joined(separator: "\n")
        XCTAssertFalse(code.contains("@discardableResult"),
                       "PrivateFile is @discardableResult again, so the compiler no longer "
                       + "objects to a dropped write and this scan is the only thing left")
        // And the hazard this guards is real only while something still answers.
        // Named, not counted: a count here would be a fact about the file that
        // goes stale the next time one is added.
        let answering = try self.answering()
        XCTAssertTrue(answering.contains("write"),
                      "the reader found \(answering) in PrivateFile and not `write` — it has "
                      + "stopped understanding the declarations, so the scan judges nothing")
        XCTAssertTrue(answering.contains("directory"), "…and not `directory`")
    }

    /// Not one call site in the app throws the answer away silently.
    func testNoCallerDropsWhatPrivateFileAnswered() throws {
        let dropped = try sites().filter(dropsTheAnswer)
        XCTAssertTrue(dropped.isEmpty,
                      "these calls drop what PrivateFile answered, so a write that never "
                      + "landed reads exactly like one that did:\n"
                      + dropped.map { "  \($0.location): \($0.text)" }.joined(separator: "\n"))
    }

    /// A discard says why it is one, in a word that says it is about the discard.
    ///
    /// This is the half that makes the rule about judgement rather than about
    /// syntax. `_ = PrivateFile.write(…)` with nothing beside it is the same
    /// oversight in a longer spelling: the next reader still cannot tell whether
    /// the author weighed the failure or never saw it.
    ///
    /// **The word is required because "there is a comment above it" is not a
    /// check.** Measured: this test first accepted any comment on the line
    /// before, and a mutation that deleted a discard's whole explanation passed
    /// it — the ordinary paragraph two lines up, about something else entirely,
    /// was enough. Code is nearly always under a comment in this repository, so
    /// that spelling could hardly fail. `Discarded` at the site is a word only
    /// somebody writing about this discard has a reason to type.
    func testEveryDiscardCarriesItsReason() throws {
        var bare: [String] = []
        let answering = try self.answering()
        for file in try RepoSource.swiftFiles(under: "Sources") {
            let lines = try RepoSource.lines(of: file)
            for (index, raw) in lines.enumerated() {
                let code = RepoSource.code(raw).trimmingCharacters(in: .whitespaces)
                // Anywhere on the line, not only at its start: one of these
                // sits inside a `forEach` closure.
                guard answering.contains(where: { code.contains("_ = PrivateFile.\($0)(") })
                else { continue }
                // The line itself, or the run of comment lines it sits under.
                var explained = raw.contains("Discard")
                var above = index - 1
                while above >= 0, lines[above].trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    explained = explained || lines[above].contains("Discard")
                    above -= 1
                }
                if !explained { bare.append("  \(file):\(index + 1): \(code)") }
            }
        }
        XCTAssertTrue(bare.isEmpty,
                      "these discard PrivateFile's answer without a comment saying, in the "
                      + "word «Discarded», why the refusal does not matter here — which reads "
                      + "the same as not having noticed:\n"
                      + bare.joined(separator: "\n"))
    }

    // MARK: - The scan is looking at something

    /// A `filter` over nothing is empty, and both rules above would pass for
    /// ever if `swiftFiles` stopped finding anything — the shape ARCHITECTURE.md
    /// § A check that cannot fail is not a check keeps warning about. So the
    /// scan says out loud that it found the calls it exists to judge.
    func testTheScanActuallyReachesTheCallSites() throws {
        let all = try sites()
        XCTAssertGreaterThan(all.count, 10,
                             "the scan found \(all.count) PrivateFile calls in Sources, which is "
                             + "fewer than the app has — it is judging an empty list")
        let files = Set(all.map(\.file))
        XCTAssertGreaterThan(files.count, 3,
                             "every call the scan found is in \(files) — it is not walking "
                             + "the whole of Sources")
    }

    /// And it can still tell a dropped answer from a used one.
    ///
    /// The reason this is here rather than left to a hand mutation: the folding
    /// above is the part that was wrong the first time, and it was wrong in the
    /// forgiving direction only after being wrong in the strict one. A scan that
    /// has been taught to accept a continuation can be taught too much, and then
    /// it accepts everything and nobody finds out. These are the shapes it has
    /// to keep apart, written down.
    func testTheScanStillKnowsADroppedAnswerWhenItSeesOne() throws {
        for statement in ["PrivateFile.write(data, to: url)",
                          "queue.async { PrivateFile.write(data, to: url) }"] {
            XCTAssertTrue(dropsTheAnswer(site(statement)),
                          "the scan reads «\(statement)» as a use, so nothing it guards is guarded")
        }
        for statement in ["_ = PrivateFile.write(data, to: url)",
                          "return PrivateFile.write(data, to: url)",
                          "guard PrivateFile.directory(at: url), PrivateFile.write(d, to: url)",
                          "let ok = PrivateFile.harden(at: url)"] {
            XCTAssertFalse(dropsTheAnswer(site(statement)),
                           "the scan reads «\(statement)» as a dropped answer, and a check that "
                           + "reports careful code is a check somebody switches off")
        }
        // A folded continuation is a use, and it is the shape the first version
        // of this scan reported seven working call sites for.
        XCTAssertFalse(dropsTheAnswer(site("let ok = PrivateFile.directory(at: url) "
                                           + "&& PrivateFile.write(d, to: url)")),
                       "a condition continued onto the next line is not a dropped answer")
    }

    private func site(_ text: String) -> Site {
        let statement = Statement(line: 1, text: text, previous: "", next: "")
        let range = text.range(of: "PrivateFile.")!
        return Site(file: "<literal>", line: 1, text: text,
                    before: String(text[text.startIndex..<range.lowerBound])
                        .trimmingCharacters(in: .whitespaces),
                    statement: statement)
    }
}
