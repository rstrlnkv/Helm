import XCTest
import HelmTestSupport

/// **«New key…» is the `+` in the window's toolbar, on the keys tab only.**
///
/// It was a bordered button alone in a strip over the key list, after every
/// other page's switchers and actions had moved into the toolbar (2026-09-16).
/// Two things can go wrong with the move, and each is a separate assertion:
/// the button stays in the page as well (two ways to make a key, one of them
/// in a strip that now says nothing else), or the `+` stays in the bar on the
/// SSH tab, where pressing it makes a key while the person is looking at a
/// different file.
///
/// Read off the construction, because a page drawn on its own has no window
/// toolbar to render the item into — `APageHeaderGoesWhereTheWindowSaysTests`
/// records the same limit.
final class NewKeyLivesInTheToolbarTests: XCTestCase {

    private let page = "Sources/Modules/Hosts/UI/HostsSettingsPage.swift"

    /// From `var <name>` to its matching brace: `SwiftSource`'s body reader
    /// covers functions and initialisers, not computed properties.
    private func property(_ name: String, in code: String) throws -> String {
        let declaration = try XCTUnwrap(code.range(of: "var \(name)"),
                                        "\(page) no longer declares \(name)")
        var depth = 0, opened = false
        var end = declaration.upperBound
        for index in code[declaration.upperBound...].indices {
            let character = code[index]
            if character == "{" { depth += 1; opened = true }
            if character == "}" { depth -= 1 }
            if opened && depth == 0 { end = code.index(after: index); break }
        }
        return String(code[declaration.lowerBound..<end])
    }

    func testTheToolbarMakesKeysOnTheKeysTabAndThePageDoesNot() throws {
        let code = SwiftSource.code(try RepoSource.text(of: page))
        let toolbar = try property("pageToolbar", in: code)

        let press = try XCTUnwrap(toolbar.range(of: "makingKey = true"), """
            the page's toolbar has no control that opens the new-key sheet — nothing on the \
            keys tab makes a key any more
            """)
        let gate = try XCTUnwrap(toolbar.range(of: "if tab == .keys"), """
            the toolbar's new-key control is not gated on the keys tab, so the `+` stays in the \
            bar over the SSH config and makes a key from a page about something else
            """)
        XCTAssertLessThan(gate.lowerBound, press.lowerBound,
                          "the keys-tab gate comes after the press it should enclose")

        let outside = code.replacingOccurrences(of: toolbar, with: "")
        XCTAssertFalse(outside.contains("makingKey = true"), """
            a control in the page still opens the new-key sheet besides the toolbar's `+` — two \
            ways to make a key, one of them in a strip over the list
            """)
    }
}
