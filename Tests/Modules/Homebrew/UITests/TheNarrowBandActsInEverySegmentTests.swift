import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The narrow package screen has three segments, and one guard reading a
/// single package is not a sweep.**
///
/// `TheNarrowPaneCanStillActOnAPackageTests` reads the installed segment in
/// depth — the verb itself, the resize invariant, Back. What it does not do is
/// walk every package in every segment: `.search` is the one place
/// `InspectorState.of` *branches* on its own — a hit already on this Mac is
/// offered `.uninstall` and a hit that is not is offered `.install`, decided
/// inside the `.search` arm rather than handed down whole the way `.installed`
/// hands down `.uninstall` — so it is the one segment where selecting one
/// package can be right and the next one wrong, and nothing swept it.
///
/// So this sweeps the cross product: every segment, every package in it, every
/// width of the band. For each selection this reads whether the narrow screen
/// replaced the list and whether it offered exactly the one action
/// `InspectorState.of` says it should — nothing, for a pinned formula; the one
/// action, for anything else — measured against a screen that is known to
/// offer nothing (the fixture's own pinned formula), so the count needs no
/// language to read: `backBar`'s own ring is the same shape at every width and
/// every segment, and what varies is only whether a second one joined it.
///
/// **The band is the same arithmetic and it is read out of the same file.**
/// 860 − 320 = 540 is the narrowest pane the settings window can be dragged to,
/// the detail item's own 420 pt is the floor under that, and `HomebrewSplit`
/// answers the top. Read rather than copied, so the day the band closes this
/// fails and says the file is about a state nobody can reach instead of passing
/// over a page that no longer has the problem.
///
/// **The search results are reached the way a person reaches them.**
/// `HomebrewSettingsPage.query` is a `@State` no test can assign, and
/// `SearchDisplay.state` draws the prompt until it is non-empty — so the mounted
/// `NSSearchField` is typed into and its change notification posted, which is
/// what SwiftUI's own coordinator behind `.searchable` listens for. A test
/// that only filled `searchHits` would sit on the prompt and read zero rows,
/// which is an absence that passes for the wrong reason; the row count is
/// asserted before any action is counted for exactly that reason.
///
/// **And the typing must be a failure when it cannot happen.** The field left
/// the page for the window's toolbar (`helmSearchable`), so the typing goes
/// through `MountedRender.type`, which reads the control off the window. This
/// used to be an `if let ... .first` over `mount.host`, which is precisely the
/// shape that goes quiet: with the field gone from the page the binding would
/// stay empty,
/// `SearchDisplay` would keep drawing the prompt, and three readings would be
/// compared on a page nobody had typed into — all of it green. So «a field was
/// expected and there is none» is an `XCTFail` naming the cell.
///
/// Which cells expect one is stated rather than discovered: the search view is
/// mounted only where there is no selection, because under the split a
/// selection replaces the whole list area with the package screen. A cell with
/// a query *and* a selection is therefore not a missing field — it is a field
/// that is correctly not there, and `expectsSearchField` is the one place that
/// says so.
@MainActor
final class TheNarrowBandActsInEverySegmentTests: XCTestCase {

    // MARK: - The fixture

    /// Answers the five queries this page puts on its way to drawing rows of
    /// all three kinds, and nothing else. Named at every construction; no
    /// default port here could reach this Mac's own brew.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)
        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
        /// One upgradeable and one pinned: `InspectorState.of` offers an action
        /// for one of the two, and nothing for the other — the pinned one also
        /// doubles as this file's "backBar alone" baseline.
        static let node = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                          isCask: false)
        static let git = OutdatedPackage(name: "git", installed: "2.54.0", latest: "2.55.0",
                                         isCask: false, pinned: true)
        /// One hit already installed and one not — the two arms of the
        /// `.search` branch, which is why this segment is worth its own cells.
        static let hits = [SearchHit(name: "wget", isCask: false),
                           SearchHit(name: "ripgrep", isCask: false)]

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([Self.wget, Self.openssl])
            case .outdated: return try JSONEncoder().encode([Self.node, Self.git])
            case .search: return try JSONEncoder().encode(Self.hits)
            // Answered, and answered empty: the description batch runs behind
            // every list refresh and an unanswered port is a refusal.
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    // MARK: - The band

    /// One integer assigned in `SettingsWindow.swift`, and a failure naming the
    /// file when the pattern does not find exactly one.
    private func windowNumber(_ pattern: String, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) -> CGFloat? {
        let path = "Sources/HelmApp/SettingsWindow.swift"
        guard let text = try? RepoSource.text(of: path) else {
            XCTFail("\(path) could not be read", file: file, line: line)
            return nil
        }
        let regex = try? NSRegularExpression(pattern: pattern)
        let all = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        guard all.count == 1, let range = Range(all[0].range(at: 1), in: text),
              let value = Double(text[range]) else {
            XCTFail("""
                \(path) has \(all.count) matches for \(what) where this reads exactly one — the \
                window's own numbers have moved and the band is being computed from a pattern \
                that no longer finds them
                """, file: file, line: line)
            return nil
        }
        return CGFloat(value)
    }

    /// The narrowest width `HomebrewSplit` answers `true` for, asked of the type
    /// rather than read off its private constant — an assertion against a
    /// declaration it also reads holds for whatever value that declaration takes.
    private var threshold: CGFloat {
        for width in stride(from: CGFloat(200), through: 1400, by: 1)
        where HomebrewSplit(availableWidth: width).showsInspector { return width }
        return 0
    }

    /// The widths a person can put this page at and still be under the split.
    /// Fails rather than skips when the band is empty: a skip reads as a pass in
    /// a failures-only summary.
    private func narrowBand(file: StaticString = #filePath, line: UInt = #line) -> [CGFloat] {
        guard let contentMin = windowNumber(#"minSize = NSSize\(width: ([0-9.]+)"#,
                                            "the window's minimum content width"),
              let sidebarMax = windowNumber(#"sidebarMaximum: CGFloat = ([0-9.]+)"#,
                                            "the sidebar's maximum thickness"),
              let detailMin = windowNumber(#"detailItem\.minimumThickness = ([0-9.]+)"#,
                                           "the detail pane's minimum thickness")
        else { return [] }
        let split = threshold
        XCTAssertGreaterThan(split, 0, "no width in 200…1400 shows the inspector",
                             file: file, line: line)
        let floor = max(detailMin, contentMin - sidebarMax)
        guard floor < split else {
            XCTFail("""
                the narrowest pane a person can reach is \(floor) pt and `HomebrewSplit` shows the \
                inspector from \(split) pt, so there is no width left where the single-column \
                branch draws. This file is then about a state the app cannot be in and should be \
                deleted rather than made green.
                """, file: file, line: line)
            return []
        }
        return [floor, ((floor + split - 1) / 2).rounded(), split - 1]
    }

    // MARK: - Reading the page

    private struct Reading {
        /// Every focus ring on the page — a bordered control, which is what
        /// `backBar`'s own glyph button is, and what every action button is.
        let rings: Int
        let lists: Int
    }

    /// Mounts the page at `width` with `segment` showing, types `query` into
    /// the search field when there is one, selects `id`, and reads what drew.
    ///
    /// Light, named: an unnamed appearance is a reading of whatever this Mac is
    /// set to at this hour (`RenderedInk`'s reason).
    private func draw(_ hb: HomebrewViewModel, _ mvm: ModuleViewModel,
                      at width: CGFloat, segment: HomebrewViewModel.Segment,
                      typing query: String? = nil, selecting id: String?,
                      file: StaticString = #filePath, line: UInt = #line) -> Reading {
        hb.segment = segment
        hb.select(id)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        mount.settle(25)
        if let query, expectsSearchField(typing: query, selecting: id) {
            // `type` posts the change notification the way AppKit delivers a
            // keystroke; assigning `stringValue` alone moves the control and
            // not the binding, so `query` would stay empty and `SearchDisplay`
            // would keep drawing the prompt.
            XCTAssertTrue(mount.type(query, turns: 25), """
                \(segment) at \(width) pt with nothing selected put no search field in the \
                window's toolbar, so «\(query)» was never typed and every reading taken from \
                this page below is of a page still showing the prompt
                """, file: file, line: line)
        }
        let lists = mount.host.everyView
            .filter { $0.appKitClassName.contains("ListCoreScrollView") }.count
        let rings = mount.host.everyView(named: "_FocusRingView").count
        mount.drop()
        return Reading(rings: rings, lists: lists)
    }

    /// Whether this cell draws a search field at all: a query is asked for, and
    /// nothing is selected. Under the split a selection replaces the list area
    /// — `searchView` with it — so a cell with both is a page that is right to
    /// have no field, and asserting one there would fail on the page working.
    private func expectsSearchField(typing query: String?, selecting id: String?) -> Bool {
        query != nil && id == nil
    }

    private func loaded() async -> (HomebrewViewModel, ModuleViewModel, Cellar) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        await hb.refreshOutdated()
        await hb.search("w")
        return (hb, mvm, transport)
    }

    /// Whether `InspectorState.of` offers an action for one package in one
    /// segment — the one place that decides, and the thing the narrow screen
    /// has to agree with. `.pinned` is not an offer: it is the badge the
    /// screen already carries.
    private func offers(_ hb: HomebrewViewModel, _ segment: HomebrewViewModel.Segment,
                        _ id: String) -> Bool {
        guard case let .package(subject) = InspectorState.of(
            segment: segment, selected: id, installed: hb.installed, outdated: hb.outdated,
            loadedOutdated: hb.loadedOutdated, hits: hb.searchHits, issues: hb.issues,
            config: hb.configGroups, descriptions: hb.descriptions)
        else { return false }
        return subject.action != .pinned
    }

    // MARK: - The cross product

    /// **Every segment, every package, every width — replaced list, right
    /// action count.**
    func testEverySegmentOffersItsSelectionsActionAtEveryWidthUnderTheSplit() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard !band.isEmpty else { return }

        let cells: [(HomebrewViewModel.Segment, [String], String?)] = [
            (.installed, hb.installed.map(\.id), nil),
            (.updates, hb.outdated.map(\.id), nil),
            (.search, hb.searchHits.map(\.id), "w"),
        ]
        // At least one package in the fixture that offers nothing, so "0
        // extra" is a fact this file checked rather than an assumption.
        XCTAssertFalse(offers(hb, .updates, Cellar.git.id), "precondition: the pinned fixture package")

        for width in band {
            XCTAssertFalse(HomebrewSplit(availableWidth: width).showsInspector, """
                \(width) pt is not under the split after all — the band was computed from the \
                window's own numbers and one of them has moved
                """)
            // `backBar` alone, read off a package that offers nothing — the
            // baseline every other reading at this width is compared against,
            // so the count below needs no language to read.
            let backOnly = draw(hb, mvm, at: width, segment: .updates, selecting: Cellar.git.id)
            XCTAssertEqual(backOnly.lists, 0, "precondition: a selection replaces the list at \(width) pt")

            for (segment, ids, query) in cells {
                XCTAssertGreaterThan(ids.count, 0, "the fixture leaves \(segment) with nothing to select")

                let none = draw(hb, mvm, at: width, segment: segment, typing: query, selecting: nil)
                XCTAssertEqual(none.lists, 1, """
                    \(none.lists) master lists drew for \(segment) at \(width) pt with nothing \
                    selected, where one is the list this whole cell is about
                    """)

                for id in ids {
                    let expectsAction = offers(hb, segment, id)
                    let reading = draw(hb, mvm, at: width, segment: segment, typing: query, selecting: id)
                    XCTAssertEqual(reading.lists, 0, """
                        selecting \(id) in \(segment) at \(width) pt still drew \(reading.lists) \
                        master lists — a selection under the split should replace the list with \
                        the package screen, not sit beside a list with no room for it
                        """)
                    let expected = backOnly.rings + (expectsAction ? 1 : 0)
                    XCTAssertEqual(reading.rings, expected, """
                        \(segment)'s screen for \(id) at \(width) pt draws \(reading.rings) \
                        controls where \(backOnly.rings) (`backBar` alone) plus \
                        \(expectsAction ? 1 : 0) (`InspectorState.of`'s own offer) is \(expected). \
                        Equal to \(backOnly.rings) is a screen offering nothing where one action \
                        was due; more is a second control nobody asked for.
                        """)
                }
            }
        }
    }
}
