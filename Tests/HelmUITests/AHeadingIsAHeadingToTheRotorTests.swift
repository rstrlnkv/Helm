// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmTestSupport
import XCTest

/// **A heading VoiceOver does not know is a heading is a page with no map.**
///
/// The rotor jumps between headings; a person who cannot use it swipes through
/// every row to find where the next section starts. Twenty places in this app
/// set `HelmText.sectionHeading` and two of them carried
/// `.accessibilityAddTraits(.isHeader)` — the two that somebody happened to
/// think about, not the two that needed it.
///
/// **It is a judgement per site and this test does not make it.** A heading that
/// introduces a group of rows is a header; a card's own name is not — a key's
/// name in `KeysTable` and a volume's name in `DiskSettingsPage` are row titles
/// that happen to be set in the heading face, and marking them would fill the
/// rotor with every row on the page, which is the same as having no rotor. What
/// this test holds is that **every site has been judged**: it carries the trait,
/// or it is written down below with the reason it does not. A twenty-first
/// heading arrives unjudged and fails here, which is the point — the default is
/// «decide», not «inherit».
///
/// **Read off the source, and the alternative was measured.** An
/// `NSHostingView`'s accessibility tree is one `AXGroup` with nothing under it,
/// recorded twice in the VPN suite and confirmed on 2026-08-20 by a probe with a
/// control: two identical stacks, one carrying the trait and one not, read
/// identically. A reading that cannot tell the fix from the defect is an
/// instrument, not an answer.
final class AHeadingIsAHeadingToTheRotorTests: XCTestCase {

    // MARK: - The judgements

    /// A heading set in the section face that is **not** a section header, and
    /// why. Keyed by the file and by what the `Text` draws, so the entry follows
    /// the line when it moves and stops matching when the line goes.
    ///
    /// Two entries share `HelmWidget.swift` + `name`, because the widget draws
    /// its own name in two layouts and the judgement is the same for both.
    private struct RowTitle {
        let file: String
        let subject: String
        /// Why it is not a section header. Read by the failure message when the
        /// record goes stale, so a stale entry says what it was excusing.
        let why: String
    }

    private static let notASectionHeader: [RowTitle] = [
        RowTitle(file: "Sources/HelmApp/HelmPanel.swift", subject: "title",
                 why: "an empty state's own sentence: there are no rows under it to introduce"),
        RowTitle(file: "Sources/HelmUI/DesignSystem/HelmWidget.swift", subject: "name",
                 why: "a widget tile's own name, in both of its layouts — a card title, not a section"),
        RowTitle(file: "Sources/Modules/KeepAwake/UI/KeepAwakeHero.swift", subject: "KAStr.customTimeTitle",
                 why: "a popover's single title, over two fields and a button: nothing to jump between"),
        RowTitle(file: "Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift", subject: "group.app.name",
                 why: "the app's own name in its row, beside its icon and its badge"),
        RowTitle(file: "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift", subject: "Redact.path(folder.path)",
                 why: "the scanned folder on a status line, beside the figures it belongs to"),
        RowTitle(file: "Sources/Modules/Disk/UI/DiskResultView.swift", subject: "dvm.displayName(for: entry)",
                 why: "the last crumb of a breadcrumb — the current folder is a fact, not a section"),
        RowTitle(file: "Sources/Modules/Disk/UI/DiskSettingsPage.swift", subject: "volume.name",
                 why: "a volume's name inside the button that scans it: a row title"),
        RowTitle(file: "Sources/Modules/Hosts/UI/KeysTable.swift", subject: "row.name",
                 why: "a key's name in its own row, beside the badges that describe it"),
        RowTitle(file: "Sources/Modules/Hosts/UI/NewKeySheet.swift", subject: "HostsStr.newKeyTitle",
                 why: "a sheet's single title: a rotor has nowhere else in the sheet to go"),
        RowTitle(file: "Sources/Modules/Hosts/UI/HostsSettingsPage.swift", subject: "HostsStr.unsaved",
                 why: "a row's title with its own note under it, not a heading over rows"),
        RowTitle(file: "Sources/Modules/Autopilot/UI/AutopilotSettingsPage.swift", subject: "Redact.path(folder.path)",
                 why: "the watched folder in its row, between the switch that names it and the buttons")
    ]

    // MARK: - The finding

    private struct Heading: Hashable {
        let file: String
        let line: Int
        let subject: String

        var described: String { "  \(file):\(line)  Text(\(subject))" }
    }

    private func headings() throws -> [Heading] {
        Self.headings(in: try read())
    }

    private func read() throws -> [(String, [String])] {
        try UISources.everyDrawnFile().map { ($0, try RepoSource.lines(of: $0)) }
    }

    /// Every place the section face is set, with what it is setting it on.
    private static func headings(in files: [(String, [String])]) -> [Heading] {
        var out: [Heading] = []
        for (file, lines) in files {
            for (index, raw) in lines.enumerated() {
                let code = RepoSource.code(raw)
                guard code.contains("HelmText.sectionHeading") else { continue }
                out.append(Heading(file: file, line: index + 1,
                                   subject: subject(at: index, in: lines) ?? "?"))
            }
        }
        return out
    }

    /// What the nearest `Text(` above draws, by paren balance — `Redact.path(f)`
    /// is one argument and it is not the first `)` on the line.
    private static func subject(at index: Int, in lines: [String]) -> String? {
        for step in 0...5 where index - step >= 0 {
            let code = RepoSource.code(lines[index - step])
            guard let opening = code.range(of: "Text(") else { continue }
            var depth = 0
            var taken = ""
            for character in code[opening.upperBound...] {
                if character == "(" { depth += 1 }
                if character == ")" {
                    if depth == 0 { return taken }
                    depth -= 1
                }
                taken.append(character)
            }
            return taken
        }
        return nil
    }

    /// A heading is judged when the chain below it carries the trait.
    private static func marked(_ heading: Heading, in lines: [String]) -> Bool {
        chain(from: heading.line - 1, in: lines).contains(".accessibilityAddTraits(.isHeader)")
    }

    /// The modifier chain the heading belongs to, by brace depth — the shape
    /// `KeyboardReachableControlsTests` walks, and for its reason: an indent
    /// walk ends at the closing brace of a multi-line closure.
    private static func chain(from index: Int, in lines: [String]) -> String {
        var text = RepoSource.code(lines[index])
        var depth = braces(in: text)
        for raw in lines.dropFirst(index + 1) {
            let code = RepoSource.code(raw)
            let body = code.trimmingCharacters(in: .whitespaces)
            if depth > 0 {
                text += "\n" + code
                depth += braces(in: code)
                continue
            }
            guard body.isEmpty || body.hasPrefix(".") else { break }
            text += "\n" + code
            depth += braces(in: code)
        }
        return text
    }

    private static func braces(in code: String) -> Int {
        code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
    }

    private static func recorded(_ heading: Heading) -> Bool {
        notASectionHeader.contains { $0.file == heading.file && $0.subject == heading.subject }
    }

    // MARK: - The rule

    func testEveryHeadingIsEitherAHeaderOrJudgedNotToBeOne() throws {
        let files = try read()
        let unjudged = Self.headings(in: files).filter { heading in
            guard let lines = files.first(where: { $0.0 == heading.file })?.1 else { return true }
            return !Self.marked(heading, in: lines) && !Self.recorded(heading)
        }

        XCTAssertEqual(unjudged.map(\.described).sorted(), [], """
            \(unjudged.count) headings are set in the section face and are neither headers to \
            VoiceOver nor written down as row titles. The rotor cannot jump to a heading that \
            does not say it is one. Add `.accessibilityAddTraits(.isHeader)` where the heading \
            introduces a group of rows, or record it in `notASectionHeader` with the reason it \
            is a row's own title.
            \(unjudged.map(\.described).sorted().joined(separator: "\n"))
            """)
    }

    /// **And the record still names something that is there.** A file renamed, a
    /// heading deleted, a `Text` rewritten — each leaves an entry excusing a site
    /// that no longer exists, and the rule above cannot tell that from a clean
    /// tree. This is the leg that can.
    func testTheRecordNamesNothingThatHasGone() throws {
        let found = try headings()

        for entry in Self.notASectionHeader {
            XCTAssertTrue(found.contains { $0.file == entry.file && $0.subject == entry.subject },
                          """
                          the record excuses `Text(\(entry.subject))` in \(entry.file) — \
                          «\(entry.why)» — and the scan finds no such heading. Either it went, \
                          in which case take the entry with it, or the scan has stopped reading \
                          this file and the rule above is passing over a shorter list than it \
                          thinks.
                          """)
        }
    }

    /// **A zero has to be a zero somebody read.** Every test above passes on a
    /// scan that reads nothing at all.
    func testTheScanIsReadingTheHeadingsOfThisApp() throws {
        let found = try headings()
        let files = Set(found.map(\.file))

        XCTAssertGreaterThanOrEqual(found.count, 20,
                                    "the scan found \(found.count) headings: \(found.map(\.described))")
        XCTAssertTrue(found.allSatisfy { $0.subject != "?" }, """
            a heading whose `Text` the scan could not read, so it can be neither marked nor \
            recorded and the record cannot name it:
            \(found.filter { $0.subject == "?" }.map(\.described).joined(separator: "\n"))
            """)
        for expected in ["Sources/Modules/Autopilot/UI/PresetSection.swift",
                         "Sources/Modules/Autopilot/UI/RuleEditor.swift",
                         "Sources/Modules/Hosts/UI/KeysTable.swift"] {
            XCTAssertTrue(files.contains(expected), "\(expected) sets no heading this scan can see")
        }
    }

    // MARK: - The rule can still fail

    func testTheRuleReadsTheTraitAndNotTheNeighbourhood() {
        let marked = """
            Text(ApStr.presetsTitle).font(HelmText.sectionHeading)
                // A heading, so the rotor can jump to it.
                .accessibilityAddTraits(.isHeader)
            """
        let bare = """
            Text(ApStr.thenLabel).font(HelmText.sectionHeading)
            ActionRow(action: $rule.action)
                .accessibilityAddTraits(.isHeader)
            """

        XCTAssertTrue(judged(marked), "the trait on the heading's own chain is not being read")
        XCTAssertFalse(judged(bare), """
            the chain ran past the heading and took the trait off the control under it, so a \
            bare heading beside a marked row reads as judged
            """)
    }

    /// Comments are stripped, and the paragraphs above quote both the face and
    /// the trait — a scan that read them would report itself.
    func testAHeadingNamedOnlyInACommentIsNotAHeading() {
        let explained = """
            // `HelmText.sectionHeading`, not `.headline`: the same 13 pt, one
            // weight apart, and `.accessibilityAddTraits(.isHeader)` is decided
            // per site.
            Text(name).font(.system(size: 13))
            """

        XCTAssertEqual(Self.headings(in: [("fixture.swift",
                                           explained.components(separatedBy: "\n"))]), [],
                       "the scan is reading comments, so it reports its own explanation")
    }

    private func judged(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        let found = Self.headings(in: [("fixture.swift", lines)])
        guard let heading = found.first else { return false }
        return Self.marked(heading, in: lines)
    }
}
