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

    /// HelmUI, every module's UI, and the app shell.
    private func drawnFiles() throws -> [String] { try UISources.everyDrawnFile() }

    private func read() throws -> [(String, [String])] {
        try drawnFiles().map { ($0, try RepoSource.lines(of: $0)) }
    }

    private func modals() throws -> [Modal] { Self.modals(in: try read()) }

    private func offenders() throws -> [Modal] { Self.offenders(in: try read()) }

    // MARK: - The scan

    private static let sheetOpeners = [".sheet("]
    private static let dialogOpeners = [".confirmationDialog(", ".alert("]

    /// Every modal presented anywhere in the drawn tree.
    private static func modals(in files: [(String, [String])]) -> [Modal] {
        var out: [Modal] = []
        let views = declarations(in: files)
        for (file, lines) in files {
            for (index, raw) in lines.enumerated() {
                let code = RepoSource.code(raw)
                let kind: Kind
                if sheetOpeners.contains(where: code.contains) {
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
        return modals(in: files).filter { modal in
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

    /// Every `struct <Name>: View` in the tree, with the code of its body.
    private static func declarations(in files: [(String, [String])]) -> [String: String] {
        var out: [String: String] = [:]
        for (_, lines) in files {
            for (index, raw) in lines.enumerated() {
                guard let name = declaredView(in: RepoSource.code(raw)) else { continue }
                out[name] = block(from: index, in: lines)
            }
        }
        return out
    }

    private static let declaration = try? NSRegularExpression(
        pattern: #"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b"#)

    private static func declaredView(in code: String) -> String? {
        guard let declaration,
              let match = declaration.firstMatch(
                in: code, range: NSRange(code.startIndex..., in: code)),
              let range = Range(match.range(at: 1), in: code) else { return nil }
        return String(code[range])
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
        var text = RepoSource.code(lines[index])
        var depth = nesting(in: text)
        guard depth > 0 else { return text }
        for raw in lines.dropFirst(index + 1) {
            let code = RepoSource.code(raw)
            text += "\n" + code
            depth += nesting(in: code)
            if depth <= 0 { break }
        }
        return text
    }

    /// The same walk from a declaration, which opens with a brace and no paren.
    private static func block(from index: Int, in lines: [String]) -> String {
        var text = RepoSource.code(lines[index])
        var depth = text.filter { $0 == "{" }.count - text.filter { $0 == "}" }.count
        for raw in lines.dropFirst(index + 1) {
            let code = RepoSource.code(raw)
            text += "\n" + code
            depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            if depth <= 0 && text.contains("{") { break }
        }
        return text
    }

    private static func nesting(in code: String) -> Int {
        code.filter { $0 == "{" || $0 == "(" }.count
            - code.filter { $0 == "}" || $0 == ")" }.count
    }

    // MARK: - The rule

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
        XCTAssertGreaterThanOrEqual(sheets.count, 5, "sheets found: \(sheets.map(\.described))")
        XCTAssertGreaterThanOrEqual(dialogs.count, 9, "dialogs found: \(dialogs.map(\.described))")
    }

    /// And the sheets are read *through* to the view they present: the scan
    /// resolves `NewKeySheet(hvm:)` to the file that declares it, or every sheet
    /// whose content is a named view is judged on a two-line closure that could
    /// never contain a shortcut, and the rule reports all of them for ever.
    func testASheetIsJudgedOnTheViewItPresents() throws {
        let presenting = try modals().filter { $0.named.contains("RuleEditor") }

        XCTAssertEqual(presenting.count, 1, """
            the scan does not resolve the view a sheet presents, so `RuleEditor` — which \
            is presented in one file and declared in another — is invisible to it
            """)
    }

    // MARK: - The rule can still fail

    /// The shape `NewKeySheet` had, past the same matcher.
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

    private func scanned(_ text: String) -> [Modal] {
        Self.offenders(in: [("fixture.swift", text.components(separatedBy: "\n"))])
    }
}
