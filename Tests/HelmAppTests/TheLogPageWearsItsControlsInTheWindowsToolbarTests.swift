import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page's controls are the window's toolbar's, like every other page's,
/// and the page under them is cards and a footer.
///
/// The page declares what it wants through `helmWindowToolbar` into a
/// `HelmWindowToolbarChannel`, and every test here reads that declaration back
/// from the channel and presses what it finds the way the toolbar does — so a
/// press goes down the wire a click in the window goes down, and a control the
/// page forgot to declare is a test that cannot find it.
final class TheLogPageWearsItsControlsInTheWindowsToolbarTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    // MARK: - What is declared

    /// Level as the centred tabs, then the capsule — module filter, Follow,
    /// Copy and the «more» menu — and the search. In every language, because the
    /// titles are looked up at the page and the toolbar has no language of its own.
    @MainActor
    func testTheToolbarCarriesTheLevelTabsTheCapsuleAndTheSearchInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let page = LogPageUnderHand(LogPageUnderHand.log())
            defer { page.close() }
            page.pump(0.6)
            let content = try XCTUnwrap(page.toolbar, "\(language.rawValue): the page declared nothing")

            XCTAssertEqual(content.tabs.map(\.id), ["all", "warn", "error"], "\(language.rawValue)")
            XCTAssertEqual(content.tabs.map(\.title),
                           [AppStr.logLevelAll, AppStr.logLevelWarnings, AppStr.logLevelErrors],
                           "\(language.rawValue)")
            XCTAssertEqual(content.selectedTab?.wrappedValue, "all", "\(language.rawValue)")
            XCTAssertEqual(content.actions.map(\.id), ["modules", "follow", "copy", "more"],
                           "\(language.rawValue)")
            XCTAssertEqual(content.search?.prompt, AppStr.logSearch, "\(language.rawValue)")
            // Every glyph-only control has a name, in the tooltip and to VoiceOver.
            XCTAssertEqual(content.actions.map(\.title),
                           [AppStr.logAllModules, AppStr.logFollow, AppStr.copyLog,
                            HelmA11y.moreActions], "\(language.rawValue)")
            guard case .menu(let more) = content.actions[3].kind else {
                return XCTFail("\(language.rawValue): «more» is not a menu")
            }
            XCTAssertEqual(more.map(\.id), ["write", "reveal", "clear"], "\(language.rawValue)")
            XCTAssertEqual(more.map(\.title),
                           [AppStr.writeLog, AppStr.revealLog, AppStr.clearLog], "\(language.rawValue)")
            // The switch moved out of a permanent band and into this menu; a dev
            // build always logs, so it is theirs to read and not to change.
            XCTAssertEqual(more[0].isEnabled, !AppBuild.isDev, "\(language.rawValue)")
        }
    }

    /// The page draws none of them itself: a level picker or a writing switch
    /// left in the body would be a second copy of a control the window owns.
    @MainActor
    func testThePageDrawsNoLevelPickerAndNoWritingSwitch() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.0)

        XCTAssertNotNil(page.scroll, "the page drew no list, so an absence of controls proves nothing")
        XCTAssertEqual(page.mount.host.everyView(ofType: NSSegmentedControl.self).count, 0,
                       "the page still draws its own level picker")
        XCTAssertEqual(page.mount.host.everyView(ofType: NSSwitch.self).count, 0,
                       "the page still draws the writing switch")
    }

    // MARK: - Pressing them

    @MainActor
    func testFollowIsAToggleWhoseLitStateIsThePagesOwn() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(0.8)
        func lit() throws -> Bool {
            guard case .toggle(let on, _) = try page.action("follow").kind else {
                XCTFail("Follow is not a toggle"); return false
            }
            return on
        }

        XCTAssertTrue(try lit(), "the page opens following")
        try page.pressFollow()
        XCTAssertFalse(try lit(), "a press did not turn Follow off in what the page declares next")
        try page.pressFollow()
        XCTAssertTrue(try lit())
    }

    @MainActor
    func testTheLevelTabsFilterAndTheSelectionReadsBack() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.0)
        let before = try XCTUnwrap(page.scroll?.documentView?.frame.height)

        try page.level(1)
        XCTAssertEqual(page.toolbar?.selectedTab?.wrappedValue, "warn")
        let warnings = try XCTUnwrap(page.scroll?.documentView?.frame.height,
                                     "half the lines are warnings, so the list must still be drawn")
        XCTAssertLessThan(warnings, before * 0.75, "Warnings did not shorten the page")

        try page.level(2)
        XCTAssertEqual(page.toolbar?.selectedTab?.wrappedValue, "error")
        XCTAssertNil(page.scroll, "no line is an error, and the page still draws a list")
        guard case .button = try page.action("copy").kind else { return XCTFail("Copy is not a button") }
        XCTAssertFalse(try page.action("copy").isEnabled, "Copy is offered over an empty page")

        try page.level(0)
        XCTAssertNotNil(page.scroll)
        XCTAssertTrue(try page.action("copy").isEnabled)
    }

    @MainActor
    func testTheSearchFiltersLiveAndAnEmptyQueryBringsEverythingBack() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.0)
        let before = try XCTUnwrap(page.scroll?.documentView?.frame.height)

        try page.search("line 397")
        let one = try XCTUnwrap(page.scroll?.documentView?.frame.height, "one line matches")
        XCTAssertLessThan(one, 250, "a query matching one line left \(one) pt of page")

        try page.search("no such thing in this log")
        XCTAssertNil(page.scroll, "nothing matches, and the page still draws a list")

        try page.search("")
        XCTAssertEqual(try XCTUnwrap(page.scroll?.documentView?.frame.height), before, accuracy: 60)
    }

    /// Built from what has arrived, and a line with no module is not a module.
    @MainActor
    func testTheModuleMenuListsTheModulesThatSpokeAndFiltersByThem() throws {
        let source = LogPageUnderHandSource()
        let start = LogPageUnderHand.start
        source.lines = [
            LogEntry(date: start, level: .info, category: "vpn", message: "network state changed"),
            LogEntry(date: start.addingTimeInterval(1), level: .info, category: "",
                     message: "Helm-OLD-FORMAT half-written line"),
            LogEntry(date: start.addingTimeInterval(2), level: .info, category: "app", message: "one"),
            LogEntry(date: start.addingTimeInterval(3), level: .info, category: "vpn", message: "two"),
        ]
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(0.8)

        guard case .menu(let items) = try page.action("modules").kind else {
            return XCTFail("the module filter is not a menu")
        }
        XCTAssertEqual(items.map(\.id), ["all", "app", "vpn"], "no entry for the unreadable line")
        XCTAssertTrue(items[0].isOn)
        XCTAssertEqual(try page.action("modules").title, AppStr.logAllModules)

        items[2].perform()   // vpn
        page.pump(0.6)
        guard case .menu(let after) = try page.action("modules").kind else {
            return XCTFail("the module filter is not a menu")
        }
        XCTAssertEqual(after.map(\.isOn), [false, false, true])
        XCTAssertEqual(try page.action("modules").title, AppStr.logSomeModules(1))
    }

    /// Clear is in the «more» menu, offered for a log that has lines or a file,
    /// and empties the page at once — the window onto the log goes with the file.
    /// Not `HelmLog.shared`'s file: a test process writes its own folder
    /// (`LogDestination`).
    ///
    /// **Between two reads.** The fake keeps answering with its lines, as a log
    /// that is written to would, so the page is only empty until its next
    /// one-second read; a press that had a read land after it proves nothing and
    /// is tried again on a fresh page.
    @MainActor
    func testClearIsInTheMoreMenuAndEmptiesThePage() throws {
        var settled = false
        for _ in 0..<6 where !settled {
            let source = LogPageUnderHand.log()
            let page = LogPageUnderHand(source)
            defer { page.close() }
            page.pump(0.8)
            XCTAssertNotNil(page.scroll, "the page drew no list, so Clear has nothing to empty")
            guard case .menu(let more) = try page.action("more").kind,
                  let clear = more.first(where: { $0.id == "clear" })
            else { return XCTFail("no Clear in the more menu") }
            XCTAssertTrue(clear.isEnabled)

            let reads = source.reads
            clear.perform()
            page.pump(0.05)
            if source.reads != reads { continue }   // a read landed in the way: try again
            XCTAssertNil(page.scroll, "Clear left lines on the page")
            settled = true
        }
        XCTAssertTrue(settled, "six presses each had a read land inside 50 ms, which is not luck")
    }

    // MARK: - The start-up fold

    /// A search is held open over every fold, and closes with the word.
    func testASearchHoldsEveryFoldOpen() {
        let id = LogEntry(date: Date(), level: .info, category: "app", message: "x").id
        XCTAssertFalse(LogView.startupIsOpen(id, opened: [], query: ""))
        XCTAssertFalse(LogView.startupIsOpen(id, opened: [], query: "   "))
        XCTAssertTrue(LogView.startupIsOpen(id, opened: [id], query: ""))
        XCTAssertTrue(LogView.startupIsOpen(id, opened: [], query: "enable"))
    }

    /// The burst is folded out of the page: the same launch drawn with the
    /// burst folded and with it broken by a warning (so nothing folds) differ
    /// by the height of the lines the fold took.
    @MainActor
    func testTheFoldTakesTheBurstOutOfThePage() throws {
        func height(interrupted: Bool) throws -> CGFloat {
            let source = LogPageUnderHandSource()
            let start = LogPageUnderHand.start
            var lines = [LogEntry(date: start, level: .info, category: "app",
                                  message: "Helm 0.11.1 started")]
            if interrupted {
                lines.append(LogEntry(date: start.addingTimeInterval(0.001), level: .warn,
                                      category: "layout", message: "no accessibility grant"))
            }
            for index in 0..<30 {
                lines.append(LogEntry(date: start.addingTimeInterval(0.01 + Double(index) * 0.01),
                                      level: .info, category: "host", message: "enable module \(index)"))
            }
            for index in 0..<3 {
                lines.append(LogEntry(date: start.addingTimeInterval(60 + Double(index)),
                                      level: .info, category: "vpn", message: "later \(index)"))
            }
            source.lines = lines
            let page = LogPageUnderHand(source)
            defer { page.close() }
            page.pump(1.0)
            return try XCTUnwrap(page.scroll?.documentView?.frame.height)
        }

        let folded = try height(interrupted: false)
        let open = try height(interrupted: true)
        print("fold: folded \(folded) pt, unfolded \(open) pt")
        // Thirty lines of at least 18 pt of type each, less the fold's own line
        // and the warning row the second draws instead.
        XCTAssertGreaterThan(open - folded, 30 * 18 - 150,
                             "the burst is drawn: \(folded) pt folded against \(open) pt")
    }

    // MARK: - Nothing cut short

    /// A message is as long as it is. The longest in a copy of the owner's log is
    /// 902 characters (the file's line, with its stamp, level and category, is
    /// 949), and the page shows exactly what the file holds.
    @MainActor
    func testALongMessageIsDrawnWholeAndNotCutToALine() throws {
        func height(words: Int) throws -> CGFloat {
            let source = LogPageUnderHandSource()
            source.lines = [LogEntry(
                date: LogPageUnderHand.start, level: .info, category: "toolbar-diag",
                message: Array(repeating: "reasserted", count: words).joined(separator: " "))]
            let page = LogPageUnderHand(source)
            defer { page.close() }
            page.pump(0.8)
            return try XCTUnwrap(page.scroll?.documentView?.frame.height)
        }
        let short = try height(words: 3)
        let long = try height(words: 90)
        XCTAssertGreaterThan(long, short + 40,
                             "a 900-character message is \(long) pt against \(short) for three words — it was cut")
    }
}
