import HelmTestSupport
import XCTest

/// **Which pages declare that nothing scrolls under their band, and why the
/// declaration is not `pageBleeds` with a nicer name.**
///
/// The rule the owner took in September 2026, measured against Finder rather
/// than guessed: the band is lit whenever the thing directly beneath it is not
/// a scroll view, and where it is one the band waits for content to go under.
/// Finder's gallery view carries the band with no column header of any kind and
/// its icon view carries neither, which is what killed the "pinned header"
/// reading; the always-on line measured α = 16/225 = 0,0711 against
/// `HeaderEdgeLight.rule`, 0,071 — one line at one alpha with several reasons.
/// `TheHeaderIsTheSystemsScrollEdgeTests` reads the predicate and the pixels.
/// This file reads the split.
///
/// # The trap this file is mostly here for
///
/// `pageBleeds` is declared by exactly eight things — seven module descriptors
/// and `LogView` — and the eight pages that need the always-on band are exactly
/// those same eight. On all thirteen pages the two answers coincide today, so
/// carrying the band on `bleeds` would pass every check anybody could write and
/// still be wrong: `bleeds` is about the header's **width**, this is about the
/// **species of the thing under it**. A field shared by coincidence fails
/// silently on the day the coincidence ends — the first full-bleed `ScrollView`
/// page, or the first column-width stack of bands — so the two are carried
/// separately, and `testNoFileDeclaresBothFacts` is what keeps them that way.
///
/// # Recorded rather than counted
///
/// Both lists are written out, and every settings page in the tree has to be on
/// one of them. A census that only counted would pass on a page that quietly
/// stopped being read, and a new module page would join the tree with no answer
/// to this question at all.
final class TheBandStandsOnWhatIsUnderItTests: XCTestCase {

    /// How a page says it: applying the modifier is the declaration, the way
    /// there is no `overContent: false` for a page handed to `helmPageHeader`.
    private static let marker = ".helmPageStandsOnStillContent()"

    /// **Eight pages whose first child under the band is a row, a toolbar or a
    /// switcher — never a scroll view.**
    ///
    /// `LogView` is the sharpest of them and the reason the rule is worth
    /// having: it publishes `HelmPageScrolledKey` as `false` and always will.
    /// It does hold a `ScrollView`, inside its lines band, but `helmPageBar` is
    /// applied to the page's outer `VStack(spacing: 0)` with that scroll view
    /// several levels inside it, so no scroll ever reaches the preference —
    /// where the pages that rely on the trigger hand a `Form` straight to
    /// `helmPageHeader`. Before this its band was structurally incapable of
    /// lighting: zero lines above the band against the page's own `Divider()`s
    /// below it.
    private static let declaring = [
        "Sources/HelmApp/LogView.swift",
        "Sources/Modules/Autopilot/UI/AutopilotSettingsPage.swift",
        "Sources/Modules/Disk/UI/DiskSettingsPage.swift",
        "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift",
        "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift",
        "Sources/Modules/Hosts/UI/HostsSettingsPage.swift",
        "Sources/Modules/Leftovers/UI/LeftoversSettingsPage.swift",
        "Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift",
    ]

    /// **Five pages that open a `Form`, a `List` or a `ScrollView` directly
    /// under the band**, where the scroll trigger the band already has is the
    /// right one and an always-on rule would be the hairline this app measured
    /// away (`ThePageHeaderCarriesNoRuleTests`) under a new name.
    ///
    /// Keep Awake, VPN and General hand over a `Form`; Layout opens one
    /// inline; About is a sheet built on a `ScrollView` and keeps its own rule
    /// for the reason recorded beside it.
    private static let notDeclaring = [
        "Sources/HelmApp/AboutPage.swift",
        "Sources/HelmApp/GeneralSettingsPage.swift",
        "Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift",
        "Sources/Modules/Layout/UI/LayoutSettingsPage.swift",
        "Sources/Modules/VPN/UI/VPNSettingsPage.swift",
    ]

    func testExactlyTheEightRecordedPagesDeclareIt() throws {
        var found: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            let code = try RepoSource.lines(of: path).map(RepoSource.code).joined(separator: "\n")
            if code.contains(Self.marker) { found.append(path) }
        }

        XCTAssertEqual(found.sorted(), Self.declaring, """
            the pages declaring that nothing scrolls under their band are \(found.sorted()), \
            not \(Self.declaring). A page that has lost the declaration has a band that waits \
            for a scroll it will never get; a page that has gained one has an always-on rule \
            over content that does scroll under it
            """)
    }

    /// Derived from the tree, so a new module cannot arrive with no answer.
    func testEverySettingsPageIsOnOneOfTheTwoLists() throws {
        let pages = try RepoSource.swiftFiles(under: "Sources/Modules")
            .filter { $0.hasSuffix("SettingsPage.swift") }
        let recorded = Set(Self.declaring + Self.notDeclaring)
        let unaccounted = pages.filter { !recorded.contains($0) }

        XCTAssertEqual(unaccounted, [], """
            \(unaccounted) draw a settings page and this file says nothing about what sits \
            under its band. Either the page stands on still content and its band never \
            lights, or it opens a scroll view and the lists above are out of date — and \
            neither is decided by whichever the page happens to do today
            """)
        XCTAssertEqual(pages.count, 10, """
            \(pages.count) module settings pages, not the ten this split was taken over — the \
            lists above are a record of a decision per page and cannot grow by themselves
            """)
    }

    /// **The trap, as a check.** The two declarations coincide on every page in
    /// the tree, so the only thing that can show they are separate facts is
    /// that they are written in separate places.
    func testNoFileDeclaresBothFacts() throws {
        var bleeding: [String] = []
        var both: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            let code = try RepoSource.lines(of: path).map(RepoSource.code).joined(separator: "\n")
            guard code.contains("pageBleeds: Bool { true }") || code.contains("bleeds: true")
            else { continue }
            bleeding.append(path)
            if code.contains(Self.marker) { both.append(path) }
        }

        XCTAssertFalse(bleeding.isEmpty, """
            nothing in the tree declares `bleeds` any more, so this check compares the band's \
            declaration against an empty set and passes for free
            """)
        XCTAssertEqual(both, ["Sources/HelmApp/LogView.swift"], """
            \(both) declare both the header's width and the species of what is under it in one \
            file. The log is the one page allowed to, because it draws the header itself and \
            has to spell both out at the call; everywhere else `bleeds` comes from a module \
            descriptor and the band's fact comes from the page, which is what stops the two \
            from being folded into one field that is right by coincidence
            """)
    }

    /// And nothing anywhere may *compute* the fact from the width — which is
    /// the shape the trap actually takes. `standsOnStillContent: bleeds` is one
    /// character's worth of work, reads as a simplification, and passes every
    /// check in this file that only counts declarations, because the answer it
    /// produces is correct on all thirteen pages.
    ///
    /// So every value handed to the argument is read, and the only three
    /// allowed are the two literals and a plain forward of the same name.
    func testNothingComputesTheFactFromTheHeadersWidth() throws {
        var values: Set<String> = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            let source = SwiftSource.uncommented(try RepoSource.text(of: path))
            var rest = Substring(source)
            while let label = rest.range(of: "standsOnStillContent:") {
                let tail = rest[label.upperBound...]
                let end = tail.firstIndex { $0 == "," || $0 == ")" || $0 == "\n" } ?? tail.endIndex
                values.insert(tail[..<end].trimmingCharacters(in: .whitespaces))
                rest = tail[end...]
            }
        }

        XCTAssertFalse(values.isEmpty, """
            nothing in the tree passes `standsOnStillContent:` at all, so this check reads an \
            empty set and passes over whatever the band is now lit by
            """)
        // `Bool` and `Bool = false` are the parameter's own declarations — the
        // stored property, the two initialisers and the predicate — which the
        // same scan cannot help reading. Named rather than filtered out by
        // shape, so a declaration appearing where none was before is visible.
        XCTAssertEqual(values.subtracting(["true", "false", "standsOnStillContent",
                                           "Bool", "Bool = false"]), [], """
            \(values.sorted()) are handed to `standsOnStillContent:`, and the only three \
            honest ones are `true`, `false` and a forward of the same name. Anything else is \
            the fact being computed — from the header's width, from a tab, from a permission \
            reading — and all three are wrong for the same reason: `bleeds` is a different \
            question that happens to agree today, and a page's first child changes shape under \
            a stationary pointer
            """)
    }

    /// The predicate itself, read separately: the four facts go in and the new
    /// one is not quietly dropped on the floor inside.
    func testThePredicateReadsTheDeclarationAndNotTheWidth() throws {
        let file = "Sources/HelmUI/DesignSystem/HelmPageHeader.swift"
        let source = SwiftSource.uncommented(try RepoSource.text(of: file))
        let body = try XCTUnwrap(SwiftSource.body(of: "isLit", in: source),
                                 "\(file) no longer declares `isLit`, so this reads nothing")

        XCTAssertFalse(body.contains("bleeds"), """
            `isLit` reads the header's width to decide whether the band is lit. The two answers \
            agree on all thirteen pages today and are different questions: `bleeds` is where \
            the header's frame ends, and this is whether anything can pass beneath it
            """)
        XCTAssertTrue(body.contains("standsOnStillContent"), """
            `isLit` no longer reads the page's declaration at all — the parameter is taken and \
            dropped, and every page that stands on still content is back to an unlit band
            """)
    }

    /// **The declaration has to reach the band that actually ships.** In the
    /// settings window the header lives in the toolbar, so the eight pages'
    /// claim is drawn by `helmToolbarBackdrop` and nowhere else; without this
    /// the whole change is inert in the one window it was made for.
    func testTheWindowsOwnBandReadsTheDeclaration() throws {
        let file = "Sources/HelmUI/DesignSystem/PageBarStyle.swift"
        let source = SwiftSource.uncommented(try RepoSource.text(of: file))
        let joined = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        XCTAssertTrue(joined.contains(".onPreferenceChange(HelmPageStandsOnStillContentKey.self) "
                                      + "{ now in standsOnStillContent = now }"), """
            `ToolbarBackdrop` no longer listens for the page's declaration, so in the settings \
            window — where every module page draws its header in the toolbar — the eight \
            declarations reach nothing at all and the band is back to lighting on scroll only
            """)
        XCTAssertTrue(joined.contains("scrolled: scrolled, "
                                      + "standsOnStillContent: standsOnStillContent"), """
            `ToolbarBackdrop` hears the declaration and does not pass it to the predicate — the \
            state is stored, the band is drawn, and nothing connects them
            """)
    }

    /// The scans above read text, and text that has been renamed reads as
    /// absent and passes everything.
    func testTheScansAreLookingForThingsThatExist() throws {
        let file = "Sources/HelmUI/DesignSystem/PageBarStyle.swift"
        let source = SwiftSource.uncommented(try RepoSource.text(of: file))

        XCTAssertTrue(source.contains("func helmPageStandsOnStillContent()"), """
            \(file) no longer declares `helmPageStandsOnStillContent`, so the census above is \
            hunting for a spelling the tree does not have and would report every page as \
            silent whatever they declare
            """)
        XCTAssertTrue(source.contains("struct HelmPageStandsOnStillContentKey"), """
            \(file) no longer declares the preference the declaration travels on, so the \
            wiring check above is reading a name that cannot appear
            """)
    }
}
