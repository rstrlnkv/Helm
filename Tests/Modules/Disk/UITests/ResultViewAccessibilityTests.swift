import XCTest
@testable import Module_Disk_UI

/// What the result screen says to somebody who is not looking at it, and what
/// it says to somebody who is looking at it in daylight.
///
/// Source scans, for the reason `NamedControlsTests` and
/// `KeyboardReachableControlsTests` give: both defects below are invisible at
/// runtime to whoever is holding the mouse. Scoped to `Sources/Modules/Disk/UI`
/// — every other module is owned by another branch in flight.
final class ResultViewAccessibilityTests: XCTestCase {

    private static var diskUI: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UITests
            .deletingLastPathComponent()   // Disk
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources/Modules/Disk/UI")
    }

    // MARK: - Colour that carries meaning

    /// "No access" was `.orange` — the system colour, which is tuned for dark
    /// and measures 2.31:1 on a light window. Ten-point body text at 2.31:1 was
    /// the worst instance in the app. `HelmSignal.warning` is the token, and it
    /// is 4.54:1 / 7.47:1 because it was solved for rather than chosen.
    func testNoTextIsPaintedWithASystemSignalColour() throws {
        let raw = ["orange", "red", "green", "yellow"]
        var offenders: [String] = []

        for url in try Self.swiftFiles() {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard raw.contains(where: { line.contains("foregroundStyle(.\($0))")
                                         || line.contains("foregroundStyle(Color.\($0))") })
                else { continue }
                offenders.append("\(url.lastPathComponent):\(index + 1)  "
                                 + line.trimmingCharacters(in: .whitespaces))
            }
        }

        XCTAssertEqual(offenders, [], """
            These paint text with a system colour built for a dark background. \
            In light mode orange measures 2.31:1 and green 2.22:1, against a \
            4.5:1 floor for body text. Use HelmSignal:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// And the rule catches the shape it was written for.
    func testTheColourRuleRecognisesTheLineItWasWrittenFor() {
        let shipped = "Text(DkStr.noAccess).font(.caption2).foregroundStyle(.orange)"
        XCTAssertTrue(shipped.contains("foregroundStyle(.orange)"))
    }

    // MARK: - A button named for what it will do

    /// The basket button was labelled "Add" in both states, so on a row already
    /// marked — where pressing it takes the item back out — VoiceOver announced
    /// the opposite of what it does.
    func testTheBasketButtonIsNamedForTheStateItIsIn() {
        XCTAssertNotEqual(DkStr.basketAction(basketed: true),
                          DkStr.basketAction(basketed: false),
                          "one name for two opposite actions")
        XCTAssertFalse(DkStr.basketAction(basketed: false).isEmpty)
        XCTAssertFalse(DkStr.basketAction(basketed: true).isEmpty)
    }

    /// And both places that draw it say so. There are two — the list row and the
    /// Advice popover's row — and they had drifted into agreeing on the wrong
    /// thing, which is what a shared pair of strings is for.
    func testEveryBasketButtonTakesItsNameAndItsTraitFromItsState() throws {
        var offenders: [String] = []

        for url in try Self.swiftFiles() {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.contains(#"basketed ? "checkmark.circle.fill""#) {
                let chain = lines.dropFirst(index).prefix(10).joined(separator: "\n")
                if !chain.contains("accessibilityLabel(DkStr.basketAction(basketed:") {
                    offenders.append("\(url.lastPathComponent):\(index + 1)  no name for the "
                                     + "state it is in")
                }
                if !chain.contains(".isSelected") {
                    offenders.append("\(url.lastPathComponent):\(index + 1)  marked, and not "
                                     + "announced as selected")
                }
            }
        }

        XCTAssertEqual(offenders, [], "\(offenders.joined(separator: "\n"))")
    }

    /// The scan must be finding both of them: a window that has stopped
    /// matching passes with nothing in it.
    func testBothBasketButtonsAreFound() throws {
        var found = 0
        for url in try Self.swiftFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            found += source.components(separatedBy: #"basketed ? "checkmark.circle.fill""#).count - 1
        }
        XCTAssertEqual(found, 2, "the list row and the Advice popover's row")
    }

    // MARK: - Actions a mouse is not required for

    /// A `.contextMenu` needs a right-click, which is a mouse. Wherever a view
    /// puts an action there it has to offer the same action somewhere VoiceOver
    /// and Full Keyboard Access can reach — `ChildRow` does exactly this and
    /// says so in a comment; the Advice popover's row, which duplicates the
    /// same Reveal, did not, so in that popover an item could be basketed and
    /// never revealed.
    func testEveryContextMenuHasAnActionThatDoesNotNeedAMouse() throws {
        var offenders: [String] = []

        for url in try Self.swiftFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            for view in Self.viewDeclarations(in: source) where view.body.contains(".contextMenu") {
                guard !view.body.contains(".accessibilityActions") else { continue }
                offenders.append("\(url.lastPathComponent): \(view.name)")
            }
        }

        XCTAssertEqual(offenders, [], """
            These offer an action only through a context menu, which needs a \
            right-click. Add the same action under .accessibilityActions:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scan has to be finding the views the rule is about — a guard that
    /// has stopped reading the source passes forever.
    func testTheScanReadsTheViewsTheRuleIsAbout() throws {
        var names: [String] = []
        for url in try Self.swiftFiles() {
            names += Self.viewDeclarations(in: try String(contentsOf: url, encoding: .utf8))
                .map(\.name)
        }
        XCTAssertTrue(names.contains("ChildRow"), "found: \(names)")
        XCTAssertTrue(names.contains("AdviceList"), "found: \(names)")
    }

    // MARK: - Source

    private struct ViewDeclaration {
        let name: String
        let body: String
    }

    /// Every `struct … : View` in a file, with everything under it. Declared at
    /// column zero, which is where all of them are; a nested one would fold
    /// into its parent, which is the safe direction — it cannot hide an
    /// offender, only report it against the outer name.
    private static func viewDeclarations(in source: String) -> [ViewDeclaration] {
        var out: [ViewDeclaration] = []
        var current: (name: String, lines: [String])?
        for line in source.components(separatedBy: "\n") {
            if let name = declaredViewName(line) {
                if let current { out.append(ViewDeclaration(name: current.name,
                                                            body: current.lines.joined(separator: "\n"))) }
                current = (name, [line])
            } else {
                current?.lines.append(line)
            }
        }
        if let current { out.append(ViewDeclaration(name: current.name,
                                                    body: current.lines.joined(separator: "\n"))) }
        return out
    }

    private static func declaredViewName(_ line: String) -> String? {
        guard !line.hasPrefix(" "), line.contains("struct "), line.contains(": View") else {
            return nil
        }
        return line.components(separatedBy: "struct ").last?
            .components(separatedBy: ":").first?
            .trimmingCharacters(in: .whitespaces)
    }

    private static func swiftFiles() throws -> [URL] {
        let files = FileManager.default.enumerator(at: diskUI, includingPropertiesForKeys: nil)
        var out: [URL] = []
        while let url = files?.nextObject() as? URL {
            if url.pathExtension == "swift" { out.append(url) }
        }
        XCTAssertGreaterThan(out.count, 5, "the disk UI moved and this test stopped looking at it")
        return out
    }
}
