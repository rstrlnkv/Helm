import XCTest

/// Every control the app draws must have a name, even when the screen shows it
/// none.
///
/// A `Picker("")` or `TextField("")` looks complete: the segments say
/// "Installed / Updates / Search" and no heading is needed above them. Read
/// aloud it is a tab group with no name, and a form built out of them cannot be
/// filled at all — the Autopilot rule editor had nine such controls, so a rule
/// could not be built by anyone using VoiceOver. Six more were in five other
/// modules; the gap was never one screen's mistake.
///
/// This is a source scan rather than a UI test because the defect is invisible
/// at runtime to anyone not using a screen reader, and the next unnamed control
/// will be added by someone who simply did not think of it. Two ways to satisfy
/// it, both correct:
///
/// - give the control its real label and hide it — `Picker(Str.thing, …)` with
///   `.labelsHidden()`, which is what that modifier is for;
/// - or `.accessibilityLabel(…)`, for a `TextField` whose first argument is
///   already spent on a placeholder.
final class NamedControlsTests: XCTestCase {

    private static let controls = ["Picker", "TextField", "SecureField", "Slider", "Stepper"]

    func testNoControlIsDrawnWithoutAName() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")
        var offenders: [String] = []

        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            guard path.contains("/UI/") || path.contains("/HelmUI/") || path.contains("/HelmApp/")
            else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")

            for (index, line) in lines.enumerated() {
                guard Self.controls.contains(where: { line.contains("\($0)(\"\")")
                                                   || line.contains("\($0)(\"\",") }) else { continue }
                // The control and everything chained onto it: modifiers are
                // indented under it and start with a dot, and a comment between
                // them is still part of the same statement.
                let indent = line.prefix { $0 == " " }.count
                var statement = line
                for next in lines.dropFirst(index + 1).prefix(40) {
                    statement += "\n" + next
                    let body = next.trimmingCharacters(in: .whitespaces)
                    let ends = !body.isEmpty
                        && next.prefix { $0 == " " }.count <= indent
                        && !body.hasPrefix(".") && !body.hasPrefix("//")
                    if ends { break }
                }
                if !statement.contains("accessibilityLabel") {
                    let name = url.lastPathComponent
                    offenders.append("\(name):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertEqual(offenders, [], """
            These controls have no name. VoiceOver reads them as "pop up button" \
            or "text field" with nothing to say what they are:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scan is worth nothing if it stops finding files.
    func testTheScanIsActuallyReadingTheSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        var seen = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            if url.pathExtension == "swift", url.path.contains("/UI/") { seen += 1 }
        }
        XCTAssertGreaterThan(seen, 20, "the source tree moved and this test stopped looking at it")
    }
}

/// An empty page is drawn by one component, not by whoever is nearest.
///
/// There were ten of these in eight shapes — spacing 10 or 14, text wrapped at
/// 360, 380, 420 or not at all, the button large in two places and not in two
/// others, one a hand-rolled `VStack` with its own `Spacer`s. Every one was
/// reasonable beside the screen it belonged to. Together they made the app look
/// assembled rather than built, and no single change would have looked wrong
/// enough for anyone to stop.
///
/// `HelmCenteredContent` is the box; `HelmEmptyState` and `HelmBusyState` are
/// what goes in it. Reaching for the box directly is how the eight shapes
/// happened, so the box stays inside the design system.
///
/// Reaching for the box was only the *tidier* half of the defect. The scan
/// looked for `HelmCenteredContent` and nothing else, so it could only ever
/// catch somebody who had already found the design system and then used the
/// wrong piece of it. The original ten included one page that centred itself
/// out of a `VStack` and a pair of bare `Spacer()`s — Homebrew's install
/// screen, which the scan was blind to for exactly as long as it existed.
///
/// So the scan describes the *shape* now: content held in the middle of a
/// `VStack` by a `Spacer()` above it and a `Spacer()` below it is an empty
/// page, whatever it is built out of.
final class OneEmptyStateTests: XCTestCase {

    /// A page that is legitimately centred by hand, and why.
    ///
    /// Nothing is here because nothing has earned it yet. A file goes in this
    /// list only with the reason written beside it — an allow-list nobody has
    /// to justify entries in becomes the way the guard is turned off.
    private static let allowed: [String: String] = [:]

    /// Offenders that exist right now and are already being replaced. Not the
    /// same list as `allowed` and deliberately not spelled the same way: these
    /// are wrong, they are known, and this list is meant to reach empty.
    ///
    /// It has. Widening the scan turned up two, of which only the first was
    /// known — and both are gone, so nothing is excused here:
    ///
    /// - `HomebrewSettingsPage.swift` — the install screen, an invitation with
    ///   a plate, a sentence and a button, which is `HelmEmptyState` exactly.
    /// - `DiskSettingsPage.swift` — `scanningState`, a spinner with a caption
    ///   *and a Stop button*. That is the fourth shape of "we are working" and
    ///   the reason `HelmBusyState` grew an `actions:` slot; it now uses it.
    ///
    /// Keyed by file rather than by line, when it has entries: another author
    /// editing anywhere above one of these must not turn this red, and neither
    /// must fixing it.
    private static let beingFixed: [String] = []

    func testNothingOutsideTheDesignSystemCentresItsOwnEmptyPage() throws {
        var offenders: [String] = []

        for url in Self.uiSources() {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = url.lastPathComponent
            guard Self.allowed[name] == nil, !Self.beingFixed.contains(name) else { continue }
            let lines = source.components(separatedBy: "\n")

            // Both call shapes. The first version of this test looked only for
            // "HelmCenteredContent(" and so was blind to the trailing-closure
            // form — which is the form every one of the eight shapes used.
            for (index, line) in lines.enumerated()
            where line.contains("HelmCenteredContent(") || line.contains("HelmCenteredContent {") {
                offenders.append("\(name):\(index + 1)  reaches for the box directly")
            }

            for (index, line) in lines.enumerated() where Self.opensAVStack(line) {
                if Self.spacersDirectlyInside(lines, from: index) >= 2 {
                    offenders.append("\(name):\(index + 1)  centres its own page "
                                     + "between two bare Spacer()s")
                }
            }
        }

        XCTAssertEqual(offenders, [], """
            These draw an empty page themselves instead of using HelmEmptyState \
            or HelmBusyState:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The guard is worth nothing if it stops reading the source, and worth
    /// less than nothing if it reads it and cannot see the shape. Both halves
    /// are checked against text, so a scan that has quietly stopped matching
    /// says so here rather than by passing.
    func testTheScanSeesBothShapes() throws {
        let handRolled = """
            private var installScreen: some View {
                VStack(spacing: 16) {
                    Spacer()
                    Text("nothing here")
                    Spacer()
                }
            }
            """.components(separatedBy: "\n")
        let opener = handRolled.firstIndex(where: Self.opensAVStack)
        XCTAssertNotNil(opener, "the VStack opener is no longer recognised")
        XCTAssertEqual(Self.spacersDirectlyInside(handRolled, from: opener ?? 0), 2)

        // A stack that merely pushes its content to one side is not an empty
        // page, and a Spacer with a length is spacing rather than centring.
        let pushed = """
            VStack {
                Spacer(minLength: 12)
                Text("a")
                Spacer(minLength: 18)
            }
            """.components(separatedBy: "\n")
        XCTAssertEqual(Self.spacersDirectlyInside(pushed, from: 0), 0)

        XCTAssertGreaterThan(Self.uiSources().count, 20,
                             "the source tree moved under this test")
    }

    /// A ledger of known offenders rots quietly: the file is renamed or deleted
    /// and the entry stays, excusing a name nothing answers to any more.
    func testTheKnownOffendersStillExist() throws {
        let names = Set(Self.uiSources().map(\.lastPathComponent))
        for offender in Self.beingFixed {
            XCTAssertTrue(names.contains(offender),
                          "\(offender) is gone — delete it from `beingFixed`")
        }
        for allowed in Self.allowed.keys {
            XCTAssertTrue(names.contains(allowed),
                          "\(allowed) is gone — delete it from `allowed`")
        }
    }

    // MARK: - The shape

    private static func opensAVStack(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard body.contains("VStack") else { return false }
        return body.hasSuffix("{")
    }

    /// Bare `Spacer()`s that are *direct children* of the stack opened at
    /// `index`, so a nested stack's own spacers do not count toward it.
    ///
    /// Indentation rather than braces: a SwiftUI body is indented by the same
    /// hand that wrote the stack, and a brace counter cannot tell a child view
    /// from a closure argument passed to one.
    private static func spacersDirectlyInside(_ lines: [String], from index: Int) -> Int {
        let outer = lines[index].prefix { $0 == " " }.count
        var childIndent: Int?
        var count = 0
        for line in lines.dropFirst(index + 1) {
            let body = line.trimmingCharacters(in: .whitespaces)
            if body.isEmpty { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent <= outer { break }              // the stack closed
            if childIndent == nil { childIndent = indent }
            guard indent == childIndent else { continue }
            if body == "Spacer()" { count += 1 }
        }
        return count
    }

    private static func uiSources() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        var found: [URL] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  !url.path.contains("/HelmUI/DesignSystem/") else { continue }
            found.append(url)
        }
        return found
    }
}
