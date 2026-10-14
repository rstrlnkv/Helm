// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmTestSupport
import XCTest

/// **A modal a keyboard cannot leave is a modal some people are stuck in.**
///
/// Escape closes a sheet on this system. Nothing in SwiftUI gives that away for
/// free: a `Button` in a sheet is an ordinary button, and the sheet stays until
/// something calls `dismiss()`. So a person who does not use a mouse has to Tab
/// to the way out and find it — past a picker, three fields and a banner, in the
/// sheet this rule was written for — and a person who uses Full Keyboard Access
/// has to do that every time the sheet opens.
///
/// Five sheets in this app bound `.keyboardShortcut(.cancelAction)` and two did
/// not, one of them written the same day as the audit that found it. That is the
/// whole reason for a scan: the ones that bind it are not more thought-through
/// than the ones that do not, they are the ones somebody happened to check.
/// `RuleEditor`'s comment even says «the two keys every sheet on this system
/// answers to» — a promise in prose, in a file that kept it, above two files
/// that did not.
///
/// **The two shapes, and why they are not the same test.**
///
/// - A **sheet** is a view this app wrote, so the way out is this app's job:
///   `.keyboardShortcut(.cancelAction)` on the button that dismisses it, or
///   `.onExitCommand` where the only way out is «Done» and there is no second
///   button to hang a shortcut on (`SidebarComposerSheet`, whose edits apply as
///   they are made, so leaving it loses nothing).
/// - An **alert** or a **confirmationDialog** is drawn by AppKit, which binds
///   Escape to the button carrying `role: .cancel` — so there the rule is that
///   such a button *exists*. All nine had one when this was written; the leg is
///   here because the day one does not is the day that dialog cannot be left
///   either, and nothing else in the suite would say so.
///
/// A source scan, for the reason `NamedControlsTests` and
/// `KeyboardReachableControlsTests` give: the defect is invisible at runtime to
/// anyone holding a mouse. It reads `UISources.everyDrawnFile()` — the design
/// system, every module's UI, and the app shell, which is where two of the five
/// sheets live.
///
/// **What the scan takes for a sheet.** A line holding `.sheet(` whose first
/// argument label, read after the paren on the same line or on the first
/// non-blank line below it, is `isPresented` or `item` — the labels of SwiftUI's
/// two overloads. Any other label marks a call of a function that happens to be
/// named `sheet` (`ShotShelf.sheet(age:)` builds a value and presents nothing),
/// which is no modal. A `.sheet(` whose label cannot be found is taken for a
/// sheet: where the scan is unsure it reports. The price is the other direction:
/// a presentation through a wrapper whose first label is some other word is not
/// seen until that word joins `presentingLabels`. Dialogs are matched by their
/// opener alone.
///
/// **One level deep, deliberately.** A sheet's source is the presentation
/// closure plus the declaration of any view it constructs there; it does not
/// recurse. A cancel button buried two views down would be a false report, and
/// there is none — a sheet's own way out belongs to the sheet.
final class EveryModalAnswersEscapeTests: XCTestCase {

    // MARK: - The finding

    private enum Kind: String { case sheet, dialog }

    private struct Modal: Hashable {
        let file: String
        let line: Int
        let kind: Kind
        let named: String

        var described: String { "  \(file):\(line)  \(kind.rawValue) \(named)" }
    }

    /// HelmUI, every module's UI, and the app shell — the files the read below
    /// covers, named separately so the reach test holds the same list the scan
    /// does rather than a second one nothing uses.
    private func drawnFiles() throws -> [String] { try read().map(\.0) }

    /// Every drawn file, as lines with comments **and the insides of string
    /// literals** blanked, every newline kept where it was.
    ///
    /// `SwiftSource.code` rather than `RepoSource.code` line by line: this scan
    /// counts braces and parentheses to find where a presentation ends, and a
    /// bracket inside a string literal, or a multi-line literal, puts that count
    /// out by one — silently, which for a guard is the failure mode that
    /// matters. Newlines survive the blanking, so a finding still names its line.
    private func read() throws -> [(String, [String])] { try Self.blanked.get() }

    /// **Read once for the whole class, not once per case.** XCTest builds a new
    /// instance per test, and blanking every drawn file is a character walk over
    /// the whole of `Sources`: measured at 2,1 s a case, which is 6,7 s across
    /// this class and 0,9 s once. A `Result` rather than an optional, so a read
    /// that fails is rethrown at the assertion instead of arriving as an empty
    /// tree — a scan over no files passes every rule it has.
    private static let blanked: Result<[(String, [String])], Error> = Result {
        try UISources.everyDrawnFile().map {
            ($0, SwiftSource.code(try RepoSource.text(of: $0)).components(separatedBy: "\n"))
        }
    }

    private func modals() throws -> [Modal] {
        let files = try read()
        return Self.modals(in: files, views: Self.declarations(in: files))
    }

    private func offenders() throws -> [Modal] { Self.offenders(in: try read()) }

    // MARK: - The scan

    private static let sheetOpener = ".sheet("
    private static let dialogOpeners = [".confirmationDialog(", ".alert("]

    /// The first argument labels of SwiftUI's two `sheet` overloads, which are the
    /// labels of a call that presents. A label outside the set marks a call of a
    /// function named `sheet`.
    ///
    /// Left out of the set, `item` turns red the `item` row, the row that follows
    /// `RuleEditor` to its declaration and the floor on the sheets found;
    /// `isPresented` turns red the rows of the last section that present through it,
    /// the row of the shape `NewKeySheet` had and the floor on the sheets found. The
    /// row that judges a fix by `item` and `isPresented` stays green either way.
    private static let presentingLabels: Set<String> = ["isPresented", "item"]

    /// Whether the line at `index` holds a `.sheet(` that presents, or one the scan
    /// cannot tell from a presentation. One such `.sheet(` on the line is enough.
    ///
    /// The first argument label is read after the paren: on the same line, or, when
    /// the paren ends the line, on the first non-blank line below it (comments are
    /// blanked before the scan, so a comment line between is blank). The receiver is
    /// never read — `self.`, `form.` and `X.` before `.sheet(` say nothing that the
    /// label does not say better.
    ///
    /// - `isPresented` or `item` followed by a colon is a sheet.
    /// - Another label followed by a colon is a call of a function named `sheet`.
    /// - No label, no colon after the word (`.sheet(makeArguments())`), or nothing
    ///   after the paren to the end of the file is taken for a sheet. The colon is
    ///   looked for on the line the word stands on: a word whose colon stands on
    ///   the next line has none.
    ///
    /// What turns it red: reading the bare text — any line with `.sheet(` is a sheet —
    /// brings back the tree row and the rows of calls named `sheet`, all but the bare
    /// call; reading the same line only brings back the call whose label is below the
    /// paren; taking a `.sheet(` it cannot classify for no sheet turns the
    /// cannot-classify row red.
    private static func opensSheet(at index: Int, in lines: [String]) -> Bool {
        let line = lines[index]
        var from = line.startIndex
        while let found = line.range(of: sheetOpener, range: from..<line.endIndex) {
            from = found.upperBound
            var tail = line[found.upperBound...].drop(while: \.isWhitespace)
            var next = index + 1
            while tail.isEmpty, next < lines.count {
                tail = lines[next].drop(while: \.isWhitespace)
                next += 1
            }
            let label = tail.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
            let colon = tail.dropFirst(label.count).drop(while: \.isWhitespace).first == ":"
            if label.isEmpty || !colon || presentingLabels.contains(String(label)) { return true }
        }
        return false
    }

    /// Every modal presented anywhere in the drawn tree: a line that `opensSheet`
    /// takes for a sheet, or, failing that, one that holds a dialog opener. A line
    /// is at most one modal, a sheet before a dialog, and a call of a function
    /// named `sheet` is none.
    ///
    /// The view map is passed in rather than built here: `offenders` needs the
    /// same one, and reading every declaration in every drawn file twice for one
    /// answer is work nobody asked for.
    private static func modals(in files: [(String, [String])],
                               views: [String: String]) -> [Modal] {
        var out: [Modal] = []
        for (file, lines) in files {
            for (index, raw) in lines.enumerated() {
                let code = raw
                let kind: Kind
                if opensSheet(at: index, in: lines) {
                    kind = .sheet
                } else if dialogOpeners.contains(where: code.contains) {
                    kind = .dialog
                } else {
                    continue
                }
                let presented = presentation(from: index, in: lines)
                let named = constructed(in: presented).filter { views[$0] != nil }
                out.append(Modal(file: file, line: index + 1, kind: kind,
                                 named: named.isEmpty ? "drawn in place" : named.joined(separator: ", ")))
            }
        }
        return out
    }

    /// The ones with no way out a keyboard can take.
    private static func offenders(in files: [(String, [String])]) -> [Modal] {
        let views = declarations(in: files)
        return modals(in: files, views: views).filter { modal in
            guard let lines = files.first(where: { $0.0 == modal.file })?.1 else { return false }
            var source = presentation(from: modal.line - 1, in: lines)
            for name in constructed(in: source) {
                if let body = views[name] { source += "\n" + body }
            }
            switch modal.kind {
            case .sheet:
                return !source.contains(".keyboardShortcut(.cancelAction)")
                    && !source.contains(".onExitCommand")
            case .dialog:
                return !source.contains("role: .cancel")
                    && !source.contains(".keyboardShortcut(.cancelAction)")
            }
        }
    }

    /// Every view in the tree, by name, with the text of its body.
    ///
    /// `SwiftSource.typeBodies` rather than a pattern for `struct X: View` and a
    /// brace walk beside it: it reads declarations with a brace **stack**, which
    /// is the only reading that survives nesting — and nesting is the normal
    /// shape here, a sheet's view declaring an enum above its own body. A view
    /// is one with a `var body: some View`: the conformance is spelled several
    /// ways and the body is spelled one.
    private static func declarations(in files: [(String, [String])]) -> [String: String] {
        var out: [String: String] = [:]
        for (_, lines) in files {
            let source = lines.joined(separator: "\n")
            let characters = Array(source)
            for body in SwiftSource.typeBodies(in: source) {
                let text = String(characters[(body.open + 1)..<body.close])
                if text.contains("var body: some View") { out[body.name] = text }
            }
        }
        return out
    }

    /// The types constructed in a piece of code — `NewKeySheet(hvm: hvm)`.
    private static let construction = try? NSRegularExpression(
        pattern: #"\b([A-Z][A-Za-z0-9_]*)\s*\("#)

    private static func constructed(in source: String) -> [String] {
        guard let construction else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        var seen: [String] = []
        for match in construction.matches(in: source, range: range) {
            guard let found = Range(match.range(at: 1), in: source) else { continue }
            let name = String(source[found])
            if !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    /// The whole presentation, from its opening line to the brace and paren it
    /// closes — a `.sheet(isPresented: Binding(get: …, set: …)) { … }` spans six
    /// lines and its content is on all of them.
    private static func presentation(from index: Int, in lines: [String]) -> String {
        var text = lines[index]
        var depth = nesting(in: text)
        guard depth > 0 else { return text }
        for raw in lines.dropFirst(index + 1) {
            text += "\n" + raw
            depth += nesting(in: raw)
            if depth <= 0 { break }
        }
        return text
    }

    private static func nesting(in code: String) -> Int {
        code.filter { $0 == "{" || $0 == "(" }.count
            - code.filter { $0 == "}" || $0 == ")" }.count
    }

    // MARK: - The rule

    /// The rule over the tree: no modal without a way out for the keyboard.
    ///
    /// It is the row that notices a scan taking too much. The bare-text reading of
    /// `.sheet(` turns it red on the line that calls a function named `sheet`. It
    /// does not notice a scan taking too little: with `item`, with `isPresented`, or
    /// with a `.sheet(` it cannot classify left out of the sheets, it stays green,
    /// because a sheet the scan does not see is not an offender. For the two labels
    /// that direction is held by the floors in the next section; the tree holds no
    /// `.sheet(` the scan cannot classify, so for those the guard is a fixture: the
    /// cannot-classify row of the last section is red when such a `.sheet(` is taken
    /// for no sheet.
    func testEveryModalCanBeLeftFromTheKeyboard() throws {
        let found = try offenders().map(\.described).sorted()

        XCTAssertEqual(found, [], """
            \(found.count) modals cannot be dismissed with Escape. A sheet needs \
            `.keyboardShortcut(.cancelAction)` on the button that leaves it, or \
            `.onExitCommand` where the only button is «Done»; an alert or a \
            confirmationDialog needs a button with `role: .cancel`, which is what AppKit \
            binds Escape to. Without one, a keyboard-only person has to find the way out \
            by Tab, every time.
            \(found.joined(separator: "\n"))
            """)
    }

    // MARK: - The scan is looking at the app

    /// **A green here has to be a green somebody read.** Every test above passes
    /// on a scan that reads nothing at all, so this is the leg that says the
    /// modals of this app reached the matcher — by name, because a count alone
    /// cannot tell «all found and clean» from «found none».
    ///
    /// A run prints one `MODAL-SCAN` line per modal found, sorted by file and line,
    /// then `MODAL-SCAN total sheets=… dialogs=… all=…`. The row asserts the file
    /// names and the floors below and compares the printed lines with nothing: they
    /// are how a change to the opener rule is read, the list before and the list
    /// after, line by line. A `.sheet(` the rule drops, or a call it adds, shows
    /// there. Without `item` or without `isPresented` among the presenting labels
    /// this row is red.
    func testTheScanFindsTheModalsThisAppDraws() throws {
        let found = try modals()
        let where_ = Set(found.map { URL(fileURLWithPath: $0.file).lastPathComponent })

        for expected in ["HostsSettingsPage.swift",        // presents NewKeySheet
                         "AutopilotSettingsPage.swift",    // presents RuleEditor
                         "AboutPage.swift",                // presents WhatsNewView
                         "GeneralSettingsPage.swift",      // presents SidebarComposerSheet
                         "DuplicatesView.swift"] {         // draws its preview in place
            XCTAssertTrue(where_.contains(expected), "no modal found in \(expected)")
        }

        let sheets = found.filter { $0.kind == .sheet }
        let dialogs = found.filter { $0.kind == .dialog }

        // Read from a run's log and compared with nothing here: one line per modal,
        // then the line of totals.
        for modal in found.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
            print("MODAL-SCAN\(modal.described)")
        }
        print("MODAL-SCAN total sheets=\(sheets.count) dialogs=\(dialogs.count) all=\(found.count)")

        XCTAssertGreaterThanOrEqual(sheets.count, 5, "sheets found: \(sheets.map(\.described))")
        XCTAssertGreaterThanOrEqual(dialogs.count, 9, "dialogs found: \(dialogs.map(\.described))")
    }

    /// And the sheets are read *through* to the view they present: the scan
    /// resolves `NewKeySheet(hvm:)` to the file that declares it, or every sheet
    /// whose content is a named view is judged on a two-line closure that could
    /// never contain a shortcut, and the rule reports all of them for ever.
    ///
    /// `RuleEditor` is presented by `.sheet(item:`, so this row is also red when
    /// `item` is not among the presenting labels.
    func testASheetIsJudgedOnTheViewItPresents() throws {
        let presenting = try modals().filter { $0.named.contains("RuleEditor") }

        XCTAssertEqual(presenting.count, 1, """
            the scan does not resolve the view a sheet presents, so `RuleEditor` — which \
            is presented in one file and declared in another — is invisible to it
            """)
    }

    // MARK: - The rule can still fail

    /// The shape `NewKeySheet` had, past the same matcher. It presents through
    /// `.sheet(isPresented:`, so it is red when that label is not among the
    /// presenting labels.
    func testTheRuleRecognisesASheetWithNoWayOut() {
        let source = """
            struct NewKeySheet: View {
                var body: some View {
                    HStack {
                        Button(HostsStr.cancel) { dismiss() }
                        Button(HostsStr.create) { create() }
                    }
                }
            }

            extension View {
                var page: some View {
                    form.sheet(isPresented: $makingKey) { NewKeySheet(hvm: hvm) }
                }
            }
            """

        XCTAssertEqual(scanned(source).map(\.line), [12],
                       "the scan cannot see the shape it was written from")
    }

    /// And the two fixes are not findings — the shortcut, and the exit command
    /// for a sheet whose only button is «Done».
    ///
    /// Both counts are zero for a scan that sees no sheet at all, so this row says
    /// that a fix is accepted and not that the sheet beside it is seen: it is green
    /// with `item` or with `isPresented` left out of the presenting labels. The rows
    /// that follow the scan to its sheets are the ones that go red there.
    func testNeitherFixIsReported() {
        let bound = """
            struct RuleEditor: View {
                var body: some View {
                    Button(ApStr.cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }

            extension View {
                var page: some View {
                    form.sheet(item: $editing) { context in RuleEditor(rule: context.rule) }
                }
            }
            """
        let exiting = """
            struct SidebarComposerSheet: View {
                var body: some View {
                    Button(AppStr.done) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .onExitCommand { dismiss() }
                }
            }

            extension View {
                var page: some View {
                    form.sheet(isPresented: $composing) { SidebarComposerSheet() }
                }
            }
            """

        XCTAssertEqual(scanned(bound).count, 0, "the bound shortcut is the fix, not a finding")
        XCTAssertEqual(scanned(exiting).count, 0, "`.onExitCommand` is the other fix")
    }

    /// A dialog is judged on `role: .cancel`, which is what AppKit gives Escape
    /// to — and nothing else in this suite says so.
    func testADialogWithoutACancelRoleIsReported() {
        let without = """
            struct Page: View {
                var body: some View {
                    form.confirmationDialog(UnStr.confirmTrash, isPresented: $asking) {
                        Button(UnStr.trash, role: .destructive) { trash() }
                    }
                }
            }
            """
        let with = """
            struct Page: View {
                var body: some View {
                    form.confirmationDialog(UnStr.confirmTrash, isPresented: $asking) {
                        Button(UnStr.trash, role: .destructive) { trash() }
                        Button(UnStr.cancel, role: .cancel) {}
                    }
                }
            }
            """

        XCTAssertEqual(scanned(without).map(\.line), [3],
                       "a dialog with no cancel role cannot be left with Escape either")
        XCTAssertEqual(scanned(with).count, 0, "the cancel role is the fix")
    }

    /// **Comments are stripped, and this is not decoration.**
    /// `LayoutSettingsPage` explains at length why its introduction stopped being
    /// `.sheet(isPresented:)`, and a scan reading comments would report that
    /// paragraph as a sheet with no way out — a finding in a file with no sheet
    /// in it.
    func testThePhantomSheetInACommentIsNotAModal() {
        let explained = """
            struct LayoutSettingsPage: View {
                /// It was `.sheet(isPresented:)`, which is a window: five of them per
                /// offscreen render, and «Got it» does exactly what it did.
                private var introSection: some View { card }
            }
            """

        XCTAssertEqual(scanned(explained).count, 0,
                       "the scan is reading comments, so it reports its own explanation")
    }

    // MARK: - What the comments of the scan say about the opener

    /// The sentences the comments above make about the opener, each asserted once
    /// with a message of its own: the class header (a wrapper under another first
    /// label is not seen; dialogs are matched by their opener alone),
    /// `opensSheet(at:in:)` (a comment line between the paren and the label is
    /// blank; one presenting `.sheet(` on a line is enough; nothing after the paren
    /// to the end of the file is a sheet; a colon on the next line is no colon) and
    /// `modals(in:views:)` (a line is at most one modal, a sheet before a dialog).
    func testTheOpenerIsReadAsItsCommentsSayIt() {
        XCTAssertEqual(modalsIn("form.sheet(isShowing: $open) { Text(\"x\") }").map(\.line), [],
                       "a `.sheet(` under the first label `isShowing:` was taken for a modal")
        XCTAssertEqual(modalsIn("let a = X.alert(age: 1)").map(\.kind), [.dialog],
                       "a dialog opener was not enough to make a dialog")

        let commented = """
            let a = X.sheet(
                // a note between the paren and the label
                age: 1
            )
            """
        XCTAssertEqual(modalsIn(commented).map(\.line), [],
                       "a comment line between the paren and the label hid the label")
        XCTAssertEqual(modalsIn("let a = X.sheet(age: 1); form.sheet(isPresented: $o) { Text(\"x\") }").map(\.kind),
                       [.sheet],
                       "a call before a presentation on one line hid the presentation")
        XCTAssertEqual(modalsIn("form.sheet(\n\n").map(\.kind), [.sheet],
                       "a `.sheet(` with nothing after the paren to the end of the file was not taken for a sheet")
        XCTAssertEqual(modalsIn("form.sheet(isPresented: $a) { Text(\"x\") }.alert(\"t\", isPresented: $b) {}").map(\.kind),
                       [.sheet],
                       "a line holding a sheet and a dialog was not exactly one modal, the sheet")
        XCTAssertEqual(modalsIn("let a = X.sheet(age\n    : 1)").map(\.kind), [.sheet],
                       "a label whose colon stands on the next line was read as a label")
    }

    // MARK: - A call of a function named `sheet` is no sheet

    // Each row below holds one direction: a call of a function named `sheet`,
    // whose first label is not a presenting one, is no modal.

    /// A static member called `sheet`, with a label that presents nothing, is no modal.
    /// Red under the bare-text reading of the opener.
    func testAStaticMemberCallNamedSheetIsNoModal() {
        XCTAssertEqual(modalsIn("let a = X.sheet(age: 1)").map(\.line), [],
                       "a static member named `sheet` was taken for a modal")
    }

    /// A method called through `self` and named `sheet` is no modal; the receiver
    /// is not what tells a call from a presentation.
    /// Red under the bare-text reading of the opener.
    func testASelfMethodCallNamedSheetIsNoModal() {
        XCTAssertEqual(modalsIn("let a = self.sheet(for: x)").map(\.line), [],
                       "a method named `sheet`, called through `self`, was taken for a modal")
    }

    /// A call whose label stands below the paren is no modal either: the label is
    /// read from the next line, or the empty tail after the paren would be taken for
    /// a sheet. Both assertions are red under the bare-text reading and under a
    /// reading of the paren's own line only.
    func testAStaticMemberCallWithItsLabelOnTheNextLineIsNoModal() {
        let source = """
            let a = X.sheet(
                age: 1
            )
            """
        XCTAssertEqual(modalsIn(source).map(\.line), [],
                       "a call with its label on the next line was taken for a modal")
        XCTAssertEqual(scanned(source).count, 0,
                       "a call with its label on the next line was reported as a sheet with no way out")
    }

    /// A bare call of a function named `sheet` is no modal. It is red when the opener
    /// is the text `sheet(` without its dot and no label is read: a line holding it is
    /// then a sheet. It is green under each reading named above `presentingLabels`
    /// and `opensSheet(at:in:)`, the bare-text one included, because the opener
    /// starts with the dot and this line has none. It does not hold the label rule.
    func testABareFunctionCallNamedSheetIsNoModal() {
        XCTAssertEqual(modalsIn("let s = sheet(of: y)").map(\.line), [],
                       "a bare call of a function named `sheet` was taken for a modal")
    }

    /// The shape the tree holds, `let sheet = ShotShelf.sheet(age: age)` in
    /// `ShotToast.swift`, is no modal and so no offender. Both assertions are red
    /// under the bare-text reading of the opener, the reading under which the tree row
    /// reports that line.
    func testTheTreesOwnShotShelfSheetCallIsNoModal() {
        XCTAssertEqual(modalsIn("let sheet = ShotShelf.sheet(age: age)").map(\.line), [],
                       "the tree's static call `ShotShelf.sheet(age:)` was taken for a modal")
        XCTAssertEqual(scanned("let sheet = ShotShelf.sheet(age: age)").count, 0,
                       "the tree's static call `ShotShelf.sheet(age:)` was reported as a sheet with no way out")
    }

    // MARK: - A presentation is still a modal

    // Each row below holds the other direction: a presentation, or a `.sheet(` the
    // scan cannot classify, is one modal of kind sheet and, with no way out in its
    // closure, an offender.

    /// `.sheet(isPresented:` is a modal and, with no way out, an offender.
    /// Red when `isPresented` is not a presenting label.
    func testSheetIsPresentedIsStillAModalWithNoWayOut() {
        let source = "form.sheet(isPresented: $open) { Text(\"x\") }"
        XCTAssertEqual(modalsIn(source).map(\.kind), [.sheet],
                       "`.sheet(isPresented:` was not taken for a sheet")
        XCTAssertEqual(scanned(source).map(\.line), [1],
                       "a `.sheet(isPresented:` with no way out was not reported")
    }

    /// `self.sheet(isPresented:` inside an extension of `View` is a modal and, with
    /// no way out, an offender; a `self.` receiver does not make it a call.
    /// Red when `isPresented` is not a presenting label.
    func testSelfSheetIsPresentedIsStillAModalWithNoWayOut() {
        let source = """
            extension View {
                func shown(_ open: Binding<Bool>) -> some View {
                    self.sheet(isPresented: open) { Text("x") }
                }
            }
            """
        XCTAssertEqual(modalsIn(source).map(\.kind), [.sheet],
                       "`self.sheet(isPresented:` was not taken for a sheet")
        XCTAssertEqual(scanned(source).map(\.line), [3],
                       "a `self.sheet(isPresented:` with no way out was not reported")
    }

    /// `.sheet(item:` is a modal and, with no way out, an offender.
    /// Red when `item` is not a presenting label, the only row of this section that is.
    func testSheetItemIsStillAModalWithNoWayOut() {
        let source = "form.sheet(item: $editing) { context in Text(context.name) }"
        XCTAssertEqual(modalsIn(source).map(\.kind), [.sheet],
                       "`.sheet(item:` was not taken for a sheet")
        XCTAssertEqual(scanned(source).map(\.line), [1],
                       "a `.sheet(item:` with no way out was not reported")
    }

    /// A `.sheet(` whose presenting label stands on the next line is a modal and an
    /// offender. Red when `isPresented` is not a presenting label. It is green with
    /// the next-line read removed: an empty tail is taken for a sheet anyway, so
    /// this row does not hold that read; the call with its label below the paren
    /// in the section above does.
    func testSheetWithItsLabelOnTheNextLineIsStillAModalWithNoWayOut() {
        let source = """
            form.sheet(
                isPresented: $open
            ) { Text("x") }
            """
        XCTAssertEqual(modalsIn(source).map(\.kind), [.sheet],
                       "a `.sheet(` with `isPresented:` on the next line was not taken for a sheet")
        XCTAssertEqual(scanned(source).map(\.line), [1],
                       "a `.sheet(` with `isPresented:` on the next line and no way out was not reported")
    }

    /// A `.sheet(isPresented: Binding(get: …` over several lines is one modal, named
    /// by the line of its opener, and an offender. Red when `isPresented` is not a
    /// presenting label.
    func testSheetWithAMultiLineBindingIsStillOneModalWithNoWayOut() {
        let source = """
            form.sheet(isPresented: Binding(
                get: { open },
                set: { open = $0 }
            )) { Text("x") }
            """
        XCTAssertEqual(modalsIn(source).map(\.kind), [.sheet],
                       "a `.sheet(isPresented: Binding(get:…` over four lines was not one sheet")
        XCTAssertEqual(scanned(source).map(\.line), [1],
                       "a `.sheet(isPresented: Binding(get:…` with no way out was not reported on its first line")
    }

    /// A `.sheet(` the scan cannot classify (`makeArguments())` is a call, not a
    /// label) is a modal and an offender: the guard leans toward reporting.
    /// Red when such a `.sheet(` is taken for no sheet; both assertions go red.
    func testASheetTheScanCannotClassifyIsStillAModalWithNoWayOut() {
        let source = "form.sheet(makeArguments())"
        XCTAssertEqual(modalsIn(source).map(\.kind), [.sheet],
                       "a `.sheet(` with no readable label was not taken for a sheet")
        XCTAssertEqual(scanned(source).map(\.line), [1],
                       "a `.sheet(` with no readable label and no way out was not reported")
    }

    /// A fixture read exactly as the tree is read, blanking and all — a fixture
    /// taking a different path would be proving a scan nothing runs. The one
    /// place a fixture becomes a file; `scanned(_:)` and `modalsIn(_:)` both
    /// read it from here.
    private func fixture(_ text: String) -> [(String, [String])] {
        [("fixture.swift", SwiftSource.code(text).components(separatedBy: "\n"))]
    }

    /// The offenders of a fixture, read through `fixture(_:)`.
    private func scanned(_ text: String) -> [Modal] {
        Self.offenders(in: fixture(text))
    }

    /// The modals a fixture holds, before any judgement of their way out: the same
    /// `modals(in:views:)` the tree goes through, over `fixture(_:)`.
    /// `scanned(_:)` adds the judgement.
    private func modalsIn(_ text: String) -> [Modal] {
        let files = fixture(text)
        return Self.modals(in: files, views: Self.declarations(in: files))
    }
}
