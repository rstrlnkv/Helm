import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The narrow branch has three segments, and one guard covered one and a half
/// of them.**
///
/// `TheNarrowPaneCanStillActOnAPackageTests` reads `.installed` at all three
/// widths of the reachable band and `.updates` at one of them; `.search` is not
/// read at any width by anything. That is the segment where `InspectorState.of`
/// *branches* — a hit already on this Mac is offered `.uninstall` and a hit that
/// is not is offered `.install`, decided inside the `.search` arm rather than
/// handed down whole the way `.installed` hands down `.uninstall` — so it is the
/// one segment where the narrow row can be right about one package and wrong
/// about the one under it, and the one segment nothing was looking at.
///
/// So this sweeps the cross product: every segment at every width of the band.
/// For each cell the rows' own actions are counted against what
/// `InspectorState.of` offers for exactly those packages, which is the same
/// comparison the installed guard makes — an absence and an invention both fail
/// it, and it does not care what the row's control is called.
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
/// what `HelmSearchField.Coordinator.controlTextDidChange` listens for. A test
/// that only filled `searchHits` would sit on the prompt and read zero rows,
/// which is an absence that passes for the wrong reason; the row count is
/// asserted before any action is counted for exactly that reason.
///
/// **Measured against 25daa5b5, 2026-09-14, three consecutive runs.** Installed
/// 2 rows / 2 actions, updates 2 rows / 1 action (one pinned), search 2 rows /
/// 2 actions, at each of 540, 550 and 559 pt. With `searchView`'s `action:`
/// argument alone removed — the repair backed out of that one list — the search
/// cells read 0 where 2 are offered and the other six cells stay green.
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
        /// for one of the two, so a row count and an offer count differ here
        /// and a check that confused them would show it.
        static let node = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                          isCask: false)
        static let git = OutdatedPackage(name: "git", installed: "2.54.0", latest: "2.55.0",
                                         isCask: false, pinned: true)
        /// One hit already installed and one not — the two arms of the
        /// `.search` branch, which is why this segment is worth its own cell.
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
        /// Focus rings inside the master list — one per bordered control a row
        /// drew. A control above the list («Upgrade all», the search field) is
        /// not one of these.
        let onRows: [CGRect]
        /// Rows of the master list, by their own cell views: "no action drew"
        /// is true of a list with no rows in it, so the rows are the subject
        /// that has to be there before the absence means anything.
        let rows: Int
        let lists: Int
    }

    /// Mounts the page at `width` with `segment` showing and nothing selected,
    /// types `query` into the search field when there is one, and reads what
    /// drew.
    ///
    /// Light, named: an unnamed appearance is a reading of whatever this Mac is
    /// set to at this hour (`RenderedInk`'s reason).
    private func draw(_ hb: HomebrewViewModel, _ mvm: ModuleViewModel,
                      at width: CGFloat, segment: HomebrewViewModel.Segment,
                      typing query: String? = nil) -> Reading {
        hb.segment = segment
        hb.select(nil)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        mount.settle(25)
        if let query, let field = mount.host.everyView(ofType: NSSearchField.self).first {
            field.stringValue = query
            // What the coordinator listens for. Assigning `stringValue` alone
            // moves the control and not the binding, so `query` would stay
            // empty and `SearchDisplay` would keep drawing the prompt.
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification,
                                            object: field)
            mount.settle(25)
        }
        var lists = 0
        var onRows: [CGRect] = []
        for (view, ancestry) in mount.host.everyViewWithAncestry {
            let insideList = ancestry.contains { $0.appKitClassName.contains("ListCoreScrollView") }
            if view.appKitClassName.contains("ListCoreScrollView") { lists += 1 }
            if insideList, view.appKitClassName == "_FocusRingView" {
                onRows.append(view.convert(view.bounds, to: mount.host))
            }
        }
        // `NSTableRowView` and not a SwiftUI class name: `List` on macOS is an
        // `NSTableView`, and its row view is the one class in this tree with a
        // public symbol to match by type rather than by text.
        let rows = mount.host.everyView(ofType: NSTableRowView.self).count
        mount.drop()
        return Reading(onRows: onRows, rows: rows, lists: lists)
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

    /// What `InspectorState.of` offers for one package in one segment — the one
    /// place that decides, and the thing the row has to agree with. `.pinned` is
    /// not an offer: it is the badge the row already carries.
    private func offers(_ hb: HomebrewViewModel, _ segment: HomebrewViewModel.Segment,
                        _ id: String) -> Bool {
        guard case let .package(subject) = InspectorState.of(
            segment: segment, selected: id, installed: hb.installed, outdated: hb.outdated,
            loadedOutdated: hb.loadedOutdated, hits: hb.searchHits, descriptions: hb.descriptions)
        else { return false }
        return subject.action != .pinned
    }

    // MARK: - The cross product

    func testEverySegmentOffersItsActionsAtEveryWidthUnderTheSplit() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard !band.isEmpty else { return }

        let cells: [(HomebrewViewModel.Segment, [String], String?)] = [
            (.installed, hb.installed.map(\.id), nil),
            (.updates, hb.outdated.map(\.id), nil),
            (.search, hb.searchHits.map(\.id), "w"),
        ]

        for (segment, ids, query) in cells {
            let expected = ids.filter { offers(hb, segment, $0) }.count
            XCTAssertGreaterThan(expected, 0, """
                the fixture leaves \(segment) with nothing `InspectorState.of` offers an action \
                for, so every count below is zero against zero and this cell cannot fail
                """)

            for width in band {
                XCTAssertFalse(HomebrewSplit(availableWidth: width).showsInspector, """
                    \(width) pt is not under the split after all — the band was computed from the \
                    window's own numbers and one of them has moved
                    """)
                let reading = draw(hb, mvm, at: width, segment: segment, typing: query)
                XCTAssertEqual(reading.lists, 1, """
                    \(reading.lists) master lists drew for \(segment) at \(width) pt, where one \
                    is the page — nothing below is a reading of the list this cell is about
                    """)
                XCTAssertEqual(reading.rows, ids.count, """
                    \(segment) drew \(reading.rows) rows at \(width) pt where the fixture holds \
                    \(ids.count) packages — «no action drew» is true of a list with no rows in it, \
                    so the count below would pass for the wrong reason
                    """)
                XCTAssertEqual(reading.onRows.count, expected, """
                    at \(width) pt the \(segment) list draws \(reading.onRows.count) actions on \
                    its rows where `InspectorState.of` offers \(expected) for the same \
                    \(ids.count) packages. Zero is the single-column branch drawing no action at \
                    all — a list below 560 pt with nothing on it to press; more than \(expected) \
                    is a narrow branch that decided for itself and offered something the \
                    inspector refuses.
                    """)
            }
        }
    }
}
