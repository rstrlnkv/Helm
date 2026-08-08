import XCTest
import HelmTestSupport

/// The extracted panel bars own no state, and it stays that way.
///
/// `PanelBars.swift` holds the rows of the card that are not tiles — the tab
/// strip, the setup bar, the gallery, the footer. They were lifted out of
/// `HelmPanel.swift`, and the whole safety of that lift is that none of them
/// gained a lifetime: a binding travels down and an action travels up.
///
/// **SwiftUI identity is what the third drag architecture was bought with**
/// (ARCHITECTURE.md § Carrying a tile). The second architecture hung the
/// gesture on the cell, a repack rebuilt the cells, the gesture died under the
/// pointer, `onEnded` never came, and the widget hung in the air. The cure was
/// putting every piece of drag state in the panel and the gesture on the grid
/// container, which nothing rebuilds. A `@State` in one of these bars is a
/// second owner of a lifetime the panel is steering by, and its failure looks
/// like the one that cost two architectures: nothing throws, nothing logs, a
/// tile is simply left in the air.
///
/// The proof of the split was `grep` in a review — one hit, inside a comment.
/// This is that grep with a runner, the way `EventNamesAreNotLiteralsTests` and
/// `ListsAgreeWithTheTreeTests` already read source for a claim no type system
/// makes.
final class PanelBarsCarryNoLifetimeTests: XCTestCase {

    /// The wrappers that make a view own something across a rebuild. Not
    /// `@Binding` or `@ObservedObject`, which are the shapes that say the owner
    /// is somewhere else — those are what these bars are supposed to use.
    private let lifetimes = ["@State", "@StateObject", "@GestureState",
                             "@FocusState", "@Namespace"]

    private func source() throws -> [String] {
        try RepoSource.lines(of: "Sources/HelmApp/PanelBars.swift")
    }

    /// Comment tails come off first: the file's own header explains the rule by
    /// naming `@State`, and a scan that reads comments reports the explanation
    /// as the offence.
    func testNoPanelBarOwnsALifetime() throws {
        let offenders = try source().enumerated()
            .map { (line: $0.offset + 1, text: RepoSource.code($0.element)) }
            .filter { line in lifetimes.contains { line.text.contains($0) } }

        XCTAssertTrue(offenders.isEmpty,
                      "a bar extracted from the panel has grown state of its own. The panel "
                      + "owns every lifetime the drag is steered by (ARCHITECTURE.md § "
                      + "Carrying a tile); pass a binding down and an action up:\n"
                      + offenders.map { "PanelBars.swift:\($0.line) —\($0.text)" }
                          .joined(separator: "\n"))
    }

    /// The control. The assertion above passes on an empty file, on a moved
    /// file and on a `code(_:)` that eats every line — and one of those is a
    /// rename away at any time.
    func testTheFileBeingReadIsTheOneWithTheBarsInIt() throws {
        let lines = try source()
        XCTAssertGreaterThan(lines.count, 100, "only \(lines.count) lines were read")
        for bar in ["struct PanelTabStrip", "struct PanelEditBar",
                    "struct PanelGallery", "struct PanelFooter"] {
            XCTAssertTrue(lines.contains { $0.contains(bar) },
                          "\(bar) is not in the file this test reads any more")
        }
    }
}
