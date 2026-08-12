import HelmTestSupport
import Module_Layout_UI
import XCTest

/// **A hotkey wired to a misspelt name is silence with no symptom at all.**
///
/// Keyboard's chord is spelled twice on each of two axes. The *slot* name is
/// what `HotkeyManager` files the binding under and what the page asks
/// `HotkeyStatus` about — the host said `"layout.fix"` and so did the page, on
/// opposite sides of a target boundary, so renaming one is an error nowhere and
/// the page's «this shortcut is already taken» warning simply stops matching.
/// The *store prefix* is worse: it is where the recorded combination lives
/// (`<prefix>KeyCode`, `<prefix>Modifiers`, `<prefix>Label`), so the host reading
/// one prefix and the page writing another means somebody records a chord, sees
/// it drawn in the row, and it does nothing — for ever.
///
/// `LayoutCommand` is already re-exported through the descriptor for exactly
/// this reason. These two names travel the same way.
///
/// Both halves are checked, and they catch different things: the values are
/// frozen because the prefix names **stored data** — a rename silently loses
/// everybody's recorded shortcut — and the scan is what stops a third copy being
/// typed next to the constant.
final class TheHotkeyNamesAreOneDeclarationTests: XCTestCase {

    /// The slot the host registers and the page asks about. Built from the
    /// module's own id and its own command, so neither can drift from it.
    func testTheSlotIsTheModuleIdAndTheCommand() {
        XCTAssertEqual(LayoutHotkey.fix, "layout.fix", """
            the hotkey slot changed name. It is not stored anywhere, so nothing breaks in \
            anybody's settings — but the host and the page have to agree on it, and this is \
            the line that says which name they agreed on.
            """)
    }

    /// **Stored data, and a shipped default.** `HelmHotkeyRecorder` writes
    /// `convertHotkeyKeyCode`, `convertHotkeyModifiers` and `convertHotkeyLabel`
    /// inside the module's store, and `HotkeyManager` reads the same three. A
    /// rename here is a chord that vanishes from a page that still draws it.
    func testTheRecordedChordKeepsTheKeysItWasSavedUnder() {
        XCTAssertEqual(LayoutHotkey.storePrefix, "convertHotkey", """
            the recorder's key prefix moved, so every shortcut anybody has already recorded is \
            now read from keys nothing writes: the row draws the stored label and the chord \
            does nothing. A new setting takes a new name; a deployed one never moves.
            """)
    }

    /// Neither name may be typed again anywhere in the tree.
    ///
    /// The shape `EventNamesAreNotLiteralsTests` scans for, one contract over.
    /// Comment tails are cut first: this file's own explanation quotes the
    /// offending string, and so does the declaration's.
    func testNeitherNameIsWrittenAsALiteralAnywhereElse() throws {
        let sources = RepoSource.root.appendingPathComponent("Sources")
        let declaration = "LayoutCommand.swift"
        var offenders: [String] = []
        var scanned = 0

        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  url.lastPathComponent != declaration,
                  let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            scanned += 1
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let text = code(line)
                for name in ["\"\(LayoutHotkey.fix)\"", "\"\(LayoutHotkey.storePrefix)\""]
                where text.contains(name) {
                    offenders.append("\(url.lastPathComponent):\(index + 1) — "
                                     + text.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        XCTAssertGreaterThan(scanned, 100,
                             "only \(scanned) source files were read, so a pass proves nothing")
        XCTAssertTrue(offenders.isEmpty, """
            a hotkey name was typed as a string. Read `LayoutHotkey` instead — it is \
            re-exported through the descriptor the way `LayoutCommand` is, so the host and the \
            page cannot spell it differently:
            \(offenders.joined(separator: "\n"))
            """)
    }

    private func code(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }
}
