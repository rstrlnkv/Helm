import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The mounted Log page, fed what its own tests did not feed: a repeat that
/// grows under Follow, the writing switch pressed on a build that is not a dev
/// build, the page in the dark and at the narrowest pane in all eight
/// languages with every counted word on screen, and a tick at a full tail.
///
/// `HELM_FRAMES_DIR=<dir>` writes what the render cases drew, with the window's
/// own background behind it so a dark frame is readable.
@MainActor
final class TheLogPageUnderInputsNobodyFedTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private static let base = LogPageUnderHand.start
    private static let grant = LogSite(file: "LayoutEngine.swift", line: 214, function: "startTap()")

    // MARK: - A repeat growing under Follow

    /// Four hundred lines, then the same warning again and again, one per tick:
    /// the newest row is one ×N row whose identity is its first line's, so it
    /// must stay one row, and Follow must stay at the end while its count and
    /// its badge grow — and with Follow off, the view must not move.
    func testARepeatGrowingUnderFollowStaysOneRowAtTheEnd() throws {
        let source = LogPageUnderHand.log()
        func repeatWarning(_ index: Int) -> LogEntry {
            LogEntry(date: Self.base.addingTimeInterval(1000 + Double(index)), level: .warn,
                     category: "layout", message: "no accessibility grant — not watching",
                     site: Self.grant)
        }
        source.lines.append(repeatWarning(0))
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(1.2)
        let height = try XCTUnwrap(page.scroll?.documentView?.frame.height)
        XCTAssertLessThanOrEqual(try page.gap(), HelmSpace.s5 + 1, "the page did not open at the end")

        for index in 1...4 {
            source.lines.append(repeatWarning(index))
            page.pump(1.2)
            let rows = LogPresentation.build(source.lines, minimumLevel: .info, categories: [], query: "")
                .cards.last?.rows
            XCTAssertEqual(rows?.last?.repeats, index + 1, "the repeat did not fold")
            XCTAssertEqual(rows?.last?.id, source.lines[400].id, "the folded row changed identity")
            XCTAssertLessThanOrEqual(try page.gap(), HelmSpace.s5 + 1,
                                     "×\(index + 1): Follow left the end of the page")
            XCTAssertEqual(try XCTUnwrap(page.scroll?.documentView?.frame.height), height,
                           accuracy: 1, "×\(index + 1): a folded repeat grew the page")
        }

        try page.pressFollow()
        try page.scrollNearTop()
        let held = try XCTUnwrap(page.scroll).documentVisibleRect.minY
        source.lines.append(repeatWarning(5))
        page.pump(1.2)
        XCTAssertEqual(try XCTUnwrap(page.scroll).documentVisibleRect.minY, held, accuracy: 0.5,
                       "with Follow off, a repeat arriving moved what the person was reading")
    }

    // MARK: - The writing switch on a build that is not a dev build

    /// A test process has no bundle version, so it is not a dev build
    /// (`AppBuild.isDev`) — which is the stable build's path: the switch in
    /// «More actions» is enabled, a press turns writing on, the next declaration says
    /// so, and the choice is stored. Pressed twice, so the process's log is
    /// left as it was found.
    func testTheWritingSwitchWorksOnABuildThatIsNotADevBuild() throws {
        XCTAssertFalse(AppBuild.isDev, "this process claims to be a dev build; the stable path is unreachable here")
        let stored = AppSettings.loggingOverride
        defer { AppSettings.loggingOverride = stored }
        let page = LogPageUnderHand(LogPageUnderHand.log(20))
        defer { page.close() }
        page.pump(0.8)
        func write() throws -> HelmToolbarMenuItem {
            guard case .menu(let more) = try page.action("more").kind,
                  let item = more.first(where: { $0.id == "write" })
            else { throw XCTSkip("no «Write a log file» in «More actions»") }
            return item
        }
        let before = try write()
        XCTAssertTrue(before.isEnabled, "the switch is greyed on a build that is not a dev build")

        before.perform()
        page.pump(0.4)
        XCTAssertEqual(try write().isOn, !before.isOn, "a press did not move the switch")
        XCTAssertEqual(AppSettings.loggingOverride, !before.isOn, "a press did not store the choice")

        try write().perform()
        page.pump(0.4)
        XCTAssertEqual(try write().isOn, before.isOn, "a second press did not move it back")
    }

    // MARK: - Clear clears the file

    /// «Clear» in «More actions» takes both files — the one being written and the
    /// rolled-over half — and not only the page. The files are the test
    /// process's own (`LogDestination` moves the folder under test); the
    /// log's queue is drained through `recentEntries()` before looking.
    func testClearInTheMoreMenuRemovesBothFilesOnDisk() throws {
        try FileManager.default.createDirectory(at: HelmLog.directory, withIntermediateDirectories: true)
        for url in HelmLog.allFileURLs {
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("x\n".utf8)))
        }
        XCTAssertTrue(HelmLog.allFileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
                      "the fixture wrote no files, so their absence below proves nothing")
        let page = LogPageUnderHand(LogPageUnderHand.log(20))
        defer { page.close() }
        page.pump(0.8)
        guard case .menu(let more) = try page.action("more").kind,
              let clear = more.first(where: { $0.id == "clear" })
        else { return XCTFail("no Clear in «More actions»") }

        clear.perform()
        _ = HelmLog.shared.recentEntries()

        let left = HelmLog.allFileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertEqual(left.map(\.lastPathComponent), [], "Clear left these on disk")
    }

    // MARK: - Eight languages, both appearances, the narrowest pane

    /// Launches whose badges count 1, 2, 5, 11 and 21 — every Russian form and
    /// the teens — a repeat, a folded start-up, a day heading, an earlier launch
    /// and a line nobody can read.
    private func counted() -> [LogEntry] {
        var lines: [LogEntry] = [
            LogEntry(date: Self.base.addingTimeInterval(-50), level: .info, category: "memory",
                     message: "sample: 143 MB (+19 MB) — no phases running"),
        ]
        var at: TimeInterval = 0
        for (launch, count) in [1, 2, 5, 11, 21].enumerated() {
            lines.append(LogEntry(date: Self.base.addingTimeInterval(at), level: .info, category: "app",
                                  message: "Helm 0.11.1-dev.\(10 + launch) started"))
            for module in 1...count {
                lines.append(LogEntry(date: Self.base.addingTimeInterval(at + Double(module) * 0.01),
                                      level: .info, category: "host", message: "enable module \(module)"))
            }
            for index in 0..<count {
                lines.append(LogEntry(date: Self.base.addingTimeInterval(at + 60 + Double(index)),
                                      level: .warn, category: "layout",
                                      message: "no accessibility grant — not watching", site: Self.grant))
            }
            lines.append(LogEntry(date: Self.base.addingTimeInterval(at + 90), level: .error,
                                  category: "uninstaller.scanLeftovers",
                                  message: "trash refused a folder: NSCocoaErrorDomain 513",
                                  site: LogSite(file: "HelmTrash.swift", line: 140, function: "remove()")))
            at += 40_000
        }
        lines.append(LogEntry(date: Self.base.addingTimeInterval(at), level: .info, category: "",
                              message: "Helm-OLD-FORMAT half-written line without a stamp or level"))
        return lines
    }

    private var framesDir: String? { ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"] }

    private func write(_ mount: MountedRender, _ name: String) {
        guard let dir = framesDir,
              let rep = mount.host.bitmapImageRepForCachingDisplay(in: mount.host.bounds) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        mount.host.cacheDisplay(in: mount.host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    /// The gutter the page's own test holds in the light, held in the dark too,
    /// in every language at both narrow panes — and each drawn for a person to
    /// read when `HELM_FRAMES_DIR` is set.
    func testTheCountedCardsFitTheNarrowestPaneInTheDarkInEveryLanguage() {
        let lines = counted()
        for width: CGFloat in [539, 645] {
            for language in AppLanguage.allCases {
                AppLanguage.override = language
                let drawn = ModulePageRender.drawn(LogView(source: { lines }, storedLog: { true }),
                                                   in: .darkAqua, width: width)
                XCTAssertGreaterThanOrEqual(drawn.layers.count, 30,
                                            "\(language.rawValue) \(width): the page drew almost nothing")
                let furthest = drawn.layers.filter { $0.frame.width < width - 1 }.map(\.frame.maxX).max() ?? 0
                XCTAssertLessThanOrEqual(furthest, width - HelmLayout.formInset + 0.5,
                                         "\(language.rawValue) \(width) dark: drawn to x = \(furthest)")
            }
        }
        guard framesDir != nil else { return }
        for appearance in RenderedInk.bothAppearances {
            for language in AppLanguage.allCases {
                AppLanguage.override = language
                let view = LogView(source: { lines }, storedLog: { true })
                    .background(Color(nsColor: .windowBackgroundColor))
                let mount = MountedRender(view, width: 539, height: 2200, appearance: appearance)
                mount.settle(80)
                write(mount, "log-539-\(language.rawValue)-\(RenderedInk.label(of: appearance))")
                mount.drop()
            }
        }
    }

    // MARK: - Two «terminating» lines in a row

    /// A picture for a person, not a gate: two builds that quit one after the
    /// other write «terminating» twice; the second stays with the launch it ends and
    /// must not draw a card of one line with no version. `HELM_FRAMES_DIR` only.
    func testTwoTerminatingLinesInARowAreDrawnForAPersonToRead() throws {
        try XCTSkipIf(framesDir == nil, "a picture only: HELM_FRAMES_DIR is not set")
        let at = { (seconds: Double) in Self.base.addingTimeInterval(seconds) }
        let lines = [
            LogEntry(date: at(0), level: .info, category: "app", message: "Helm 0.11.1-dev.14 started"),
            LogEntry(date: at(0.1), level: .info, category: "host", message: "enable vpn"),
            LogEntry(date: at(300), level: .info, category: "memory",
                     message: "sample: 88 MB (+65 MB) — no phases running"),
            LogEntry(date: at(600), level: .info, category: "app", message: "terminating"),
            LogEntry(date: at(600.049), level: .info, category: "app", message: "terminating"),
            LogEntry(date: at(900), level: .info, category: "app", message: "Helm 0.11.1-dev.15 started"),
            LogEntry(date: at(900.1), level: .info, category: "host", message: "enable vpn"),
        ]
        let page = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: "")
        XCTAssertEqual(page.cards.map(\.session.lines.count), [5, 2], "the fixture's split changed")
        for appearance in RenderedInk.bothAppearances {
            for language in [AppLanguage.en, .ru] {
                AppLanguage.override = language
                let view = LogView(source: { lines }, storedLog: { true })
                    .background(Color(nsColor: .windowBackgroundColor))
                let mount = MountedRender(view, width: 645, height: 700, appearance: appearance)
                mount.settle(80)
                write(mount, "log-two-terminating-\(language.rawValue)-\(RenderedInk.label(of: appearance))")
                mount.drop()
            }
        }
    }

    // MARK: - Follow switched off between its two landings

    /// **Follow switched off between its two landings is not landed again.** A
    /// line arriving into a full tail can land the view at the end twice: once
    /// in the change handler, and once more after a hop to the main queue,
    /// because the first landing stops where the lazy stack's estimate put the
    /// end. A person who turns Follow off in between must not be carried on:
    /// whether Follow is lit is a reading, and it has to be read after the hop.
    ///
    /// The window is made on purpose. The page reads its source on its tick and
    /// the handler runs in that update and queues its hop; the main queue is
    /// served only when the run loop wakes again. An observer ordered after
    /// every other in the before-waiting pass, on the first pass after a read
    /// that brought the new line, sees the first landing done and the hop not
    /// yet run, and presses Follow off there.
    ///
    /// Two shapes where the first landing can fall short — a line on a new day,
    /// which brings a heading, and a line that wraps — pumped the way this
    /// page's own Follow tests pump it, with layout forced between run-loop
    /// turns. Pumped by the run loop alone in a window that is never ordered in,
    /// the first landing was exact in every shape tried, so there is no second
    /// landing there to interrupt, and this cannot be asked of that pump. (A
    /// window that *is* on screen is a different pump with a different answer:
    /// `TheLogOpensOnItsNewestLineInARealWindowTests`.)
    ///
    /// Whether the first landing falls short is the layout's timing, not the
    /// input's: some passes land exactly. So the press is made on every try,
    /// the view must never move after it, and a try counts as evidence only when
    /// the view was left short of the end — a second landing was due and did not
    /// come. At least one such try is required, or the test proves nothing.
    func testFollowSwitchedOffBetweenItsTwoLandingsIsNotLandedAgain() throws {
        let at = Self.base.addingTimeInterval(1000)
        let shapes: [(String, LogEntry)] = [
            ("a line on a new day", LogEntry(date: at.addingTimeInterval(86_400), level: .info,
                                             category: "app", message: "line 1000")),
            ("a line that wraps", LogEntry(date: at, level: .warn, category: "app",
                                           message: Array(repeating: "a long wrapped word", count: 40)
                                               .joined(separator: " "))),
        ]
        var due = 0, tries: [String] = []
        for attempt in 0..<8 {
            let (label, arriving) = shapes[attempt % shapes.count]
            let landed = try landings(arriving)
            tries.append("\(label): y \(landed.at) → \(landed.after), \(landed.gap) pt from the end")
            XCTAssertEqual(landed.after, landed.at, accuracy: 1, """
                \(label): Follow was switched off after the first landing (y = \(landed.at)) and \
                before the second, and the view was carried on to y = \(landed.after) anyway
                """)
            if landed.gap > HelmSpace.s5 + 1 { due += 1 }
            if due >= 2 { break }
        }
        print("Follow off between the landings — " + tries.joined(separator: "; "))
        XCTAssertGreaterThan(due, 0, """
            no try left the first landing short of the end, so no second landing was ever due \
            and the press proved nothing: \(tries)
            """)
    }

    private func landings(_ arriving: LogEntry) throws -> (at: CGFloat, after: CGFloat, gap: CGFloat) {
        let source = LogPageUnderHandSource()
        source.lines = (0..<1000).map { index in
            LogEntry(date: Self.base.addingTimeInterval(Double(index)), level: index % 2 == 1 ? .warn : .info,
                     category: "app", message: "line \(index)")
        }
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24, "the full tail did not open on its newest line")
        let scroll = try XCTUnwrap(page.scroll)
        guard case .toggle(let lit, let pressFollow) = try page.action("follow").kind else {
            XCTFail("Follow is not a toggle in the capsule")
            return (0, 0, 0)
        }
        XCTAssertTrue(lit, "Follow is not lit on a page that has just opened")

        let window = LandingWindow(scroll: scroll, source: source, press: pressFollow)
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            MainActor.assumeIsolated { window.fire() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        defer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        window.readsBefore = source.reads
        source.lines.append(arriving)
        source.lines.removeFirst()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !window.fired {
            page.mount.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(window.fired, "the page never read the new line")
        page.pump(1.2)
        guard case .toggle(let still, _) = try page.action("follow").kind else { return (0, 0, 0) }
        XCTAssertFalse(still, "Follow is still lit after the press")
        return (window.at, scroll.documentVisibleRect.minY, try page.gap())
    }

    /// What the observer between the two landings reaches, and what it saw.
    private final class LandingWindow: @unchecked Sendable {
        let scroll: NSScrollView
        let source: LogPageUnderHandSource
        let press: () -> Void
        var readsBefore = Int.max
        var fired = false
        var at: CGFloat = 0
        init(scroll: NSScrollView, source: LogPageUnderHandSource, press: @escaping () -> Void) {
            self.scroll = scroll
            self.source = source
            self.press = press
        }
        func fire() {
            guard !fired, source.reads > readsBefore else { return }
            fired = true
            at = scroll.documentVisibleRect.minY
            press()
        }
    }

    // MARK: - A tick at a full tail

    /// The longest single turn of the main run loop in which the page read its
    /// source and something had changed — the cost of one tick of the page, at
    /// the cap, while one line arrives per tick and the oldest leaves. Three
    /// shapes: one launch that has been running long enough to fill the tail
    /// (so the only card is the tail's head, whose identity is one constant
    /// while its oldest line changes on every tick), twelve launches, and a
    /// quiet tail.
    ///
    /// A report: `HELM_BENCH=1`. It fails only when a tick costs more than the
    /// tick's own interval, which is a page that can no longer keep up.
    func testOneTickAtAFullTailCosts() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        func tail(launches: Int) -> [LogEntry] {
            (0..<1000).map { index in
                let every = 1000 / max(launches, 1)
                if launches > 0, index % every == 0 {
                    return LogEntry(date: Self.base.addingTimeInterval(Double(index) * 4.7), level: .info,
                                    category: "app", message: "Helm 0.11.1-dev.\(index / every) started")
                }
                return LogEntry(date: Self.base.addingTimeInterval(Double(index) * 4.7),
                                level: index % 97 == 0 ? .warn : .info,
                                category: ["vpn", "memory", "host", "layout"][index % 4],
                                message: "sample: \(index % 300) MB — no phases running")
            }
        }
        var report: [String] = []
        for (label, launches, rotating) in [("one long launch", 0, true), ("twelve launches", 12, true),
                                            ("quiet", 12, false)] {
            let source = LogPageUnderHandSource()
            source.lines = tail(launches: launches)
            var next = 0
            let mount = MountedRender(
                LogView(source: {
                    source.reads += 1
                    if rotating {
                        next += 1
                        source.lines.removeFirst()
                        source.lines.append(LogEntry(date: Date(), level: .info, category: "vpn",
                                                     message: "network state changed \(next)"))
                    }
                    return source.lines
                }, storedLog: { true }),
                width: 645, height: 700, appearance: .aqua)
            defer { mount.drop() }
            // Warm-up: the first mount pays for the fonts and the first render.
            let warm = Date().addingTimeInterval(4)
            while Date() < warm {
                mount.host.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            var ticks: [Double] = []
            let end = Date().addingTimeInterval(10)
            while Date() < end {
                let reads = source.reads
                let began = CFAbsoluteTimeGetCurrent()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
                mount.host.layoutSubtreeIfNeeded()
                mount.host.displayIfNeeded()
                let took = (CFAbsoluteTimeGetCurrent() - began) * 1000
                if source.reads != reads { ticks.append(took) }
            }
            XCTAssertGreaterThanOrEqual(ticks.count, 8, "\(label): the page's tick fired \(ticks.count) times in 10 s")
            let sorted = ticks.sorted()
            report.append(String(format: "%@: %d ticks, median %.1f ms, worst %.1f ms", label, ticks.count,
                                 sorted.isEmpty ? 0 : sorted[sorted.count / 2], sorted.last ?? 0))
            XCTAssertLessThan(sorted.last ?? 0, 1000, "\(label): one tick took longer than the tick's interval")
        }
        print("log page tick at 1000 lines — " + report.joined(separator: "; "))
    }
}
