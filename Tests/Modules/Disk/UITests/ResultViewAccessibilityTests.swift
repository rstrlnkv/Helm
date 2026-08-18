import HelmTestSupport
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
        XCTAssertNotEqual(DkStr.basketAction(name: "Downloads", basketed: true),
                          DkStr.basketAction(name: "Downloads", basketed: false),
                          "one name for two opposite actions")
        XCTAssertFalse(DkStr.basketAction(name: "Downloads", basketed: false).isEmpty)
        XCTAssertFalse(DkStr.basketAction(name: "Downloads", basketed: true).isEmpty)
    }

    /// And wherever it is drawn, it says so.
    ///
    /// This used to read «both places», because there were two — the list row and
    /// the Advice popover's row, written out separately and drifted into agreeing
    /// on the wrong thing. They are one `BasketButton` now, so the drift this
    /// scan was compensating for is not available: the count below is what makes
    /// that a rule rather than today's arrangement.
    func testEveryBasketButtonTakesItsNameAndItsTraitFromItsState() throws {
        var offenders: [String] = []

        for url in try Self.swiftFiles() {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.contains(#"basketed ? "checkmark.circle.fill""#) {
                let chain = lines.dropFirst(index).prefix(10).joined(separator: "\n")
                if !chain.contains("accessibilityLabel(DkStr.basketAction(name:") {
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

    /// **One drawing, two doors.** The scan above must be finding something — a
    /// window that has stopped matching passes with nothing in it — and what it
    /// has to find is exactly one, because a second copy is how the names drifted
    /// the first time and how `.disabled` came to be remembered at neither.
    func testTheBasketButtonIsDrawnOnceAndReachedFromTwoRows() throws {
        var drawings = 0
        var uses = 0
        for url in try Self.swiftFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            drawings += source.components(separatedBy: #"basketed ? "checkmark.circle.fill""#).count - 1
            uses += source.components(separatedBy: "BasketButton(name:").count - 1
        }
        XCTAssertEqual(drawings, 1,
                       "the mark button is drawn in \(drawings) places; anything true of it — "
                       + "its name, its trait, whether it dims during a removal — then has to "
                       + "be remembered at each")
        XCTAssertEqual(uses, 2, "the list row and the Advice popover's row both reach it")
    }

    // MARK: - Actions a mouse is not required for

    /// A `.contextMenu` needs a right-click, which is a mouse. Wherever a view
    /// puts an action there it has to offer *that action* somewhere VoiceOver
    /// and Full Keyboard Access can reach: the Advice popover's row duplicated
    /// `ChildRow`'s Reveal and offered it nowhere else, so in that popover an
    /// item could be basketed and never looked at.
    ///
    /// **Named actions, not a named modifier, and code rather than prose.** This
    /// asked only whether the view mentioned `.accessibilityActions` anywhere —
    /// which `ChildRow` satisfied with a *comment* about the accessibility
    /// action it had just replaced with a Button, on a scan that read comments.
    /// Both halves of that were wrong: a rule looking for one modifier cannot
    /// see that a `Button` in the row is the better answer to the same question,
    /// and a rule that reads comments is answered by its own explanation. Every
    /// name a menu builds a `Button` from must appear outside that menu — in an
    /// `.accessibilityActions`, or in a control the row draws.
    func testEveryContextMenuActionIsOfferedWhereAMouseIsNotNeeded() throws {
        var offenders: [String] = []

        for url in try Self.swiftFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            for view in Self.viewDeclarations(in: source) {
                for menu in Self.menus(in: view.body) {
                    let elsewhere = view.body.replacingOccurrences(of: menu, with: "")
                    let (named, unreadable) = Self.buttonNames(in: menu)
                    for action in named where !elsewhere.contains(action) {
                        offenders.append("\(url.lastPathComponent): \(view.name) — \(action) "
                                         + "is in the menu and nowhere else")
                    }
                    if unreadable > 0 {
                        offenders.append("\(url.lastPathComponent): \(view.name) — \(unreadable) "
                                         + "menu button(s) this rule cannot read a name from")
                    }
                }
            }
        }

        XCTAssertEqual(offenders, [], """
            These offer an action only through a context menu, which needs a \
            right-click. Offer the same action as a Button in the view, or under \
            .accessibilityActions:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// And the rule reads the menus it is about, so "no offenders" is not "no
    /// menus". Both rows put their Reveal in one.
    func testTheMenuScanFindsTheMenusAndTheirActions() throws {
        var actions: [String] = []
        for url in try Self.swiftFiles() {
            for view in Self.viewDeclarations(in: try String(contentsOf: url, encoding: .utf8)) {
                for menu in Self.menus(in: view.body) {
                    actions += Self.buttonNames(in: menu).named
                }
            }
        }

        XCTAssertTrue(actions.contains("HelmA11y.showInFinder"),
                      "no Reveal in any menu the scan can see: \(actions)")
        XCTAssertTrue(actions.contains("DkStr.openFolder"), "found: \(actions)")
        XCTAssertGreaterThanOrEqual(actions.count, 3, "found: \(actions)")
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

    /// The `.contextMenu { … }` blocks of a view, brace-counted, so a menu with
    /// two Buttons on separate lines is one block rather than one line.
    private static func menus(in body: String) -> [String] {
        var out: [String] = []
        let lines = body.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains(".contextMenu") {
            var text = line
            var depth = braces(in: line)
            for next in lines.dropFirst(index + 1) {
                guard depth > 0 else { break }
                text += "\n" + next
                depth += braces(in: next)
            }
            out.append(text)
        }
        return out
    }

    private static func braces(in line: String) -> Int {
        line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
    }

    /// What a menu's buttons are named — `Button(DkStr.openFolder)` gives
    /// `DkStr.openFolder` — and how many it could not read, because a button
    /// this rule cannot name is a hole in it rather than a pass.
    private static func buttonNames(in menu: String) -> (named: [String], unreadable: Int) {
        var named: [String] = []
        var unreadable = 0
        for fragment in menu.components(separatedBy: "Button(").dropFirst() {
            let argument = fragment.components(separatedBy: ")").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let parts = argument.components(separatedBy: ".")
            guard parts.count == 2, let first = parts[0].first, first.isUppercase,
                  parts[1].allSatisfy({ $0.isLetter || $0.isNumber }), !parts[1].isEmpty else {
                unreadable += 1
                continue
            }
            named.append(argument)
        }
        return (named, unreadable)
    }

    /// Every `struct … : View` in a file, with everything under it **and its
    /// comments stripped**. Declared at column zero, which is where all of them
    /// are; a nested one would fold into its parent, which is the safe direction
    /// — it cannot hide an offender, only report it against the outer name.
    ///
    /// The stripping is not tidiness. This repository explains a rule by naming
    /// the thing it forbids, right above the line that obeys it, so a scan that
    /// reads comments is answered by the explanation: `ChildRow` passed the menu
    /// rule for a day on a comment about the accessibility action it no longer
    /// had.
    private static func viewDeclarations(in source: String) -> [ViewDeclaration] {
        var out: [ViewDeclaration] = []
        var current: (name: String, lines: [String])?
        for raw in source.components(separatedBy: "\n") {
            let line = RepoSource.code(raw)
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
