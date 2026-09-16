import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Dragging the window past the narrow band reorganised the page twice.**
///
/// Two boundaries, and neither was wrong on its own. `HomebrewSplit` dropped the
/// inspector at 560 pt, a floor measured against the real page; the header
/// exchanged its segmented switcher for a menu wherever the segments stopped
/// fitting, which is a different width in every language. Swept a point at a
/// time on the real page, 2026-09-16: en, zh and de below 400 pt · fr 466 ·
/// pt 482 · es 554 · **ru 566** · **ja 572**. So a Russian window dragged across
/// 560…566 lost its second column and then changed its switcher six points
/// later, and a Japanese one did it across twelve.
///
/// **The repair is that one question answers both.** `headerBar` puts
/// `HomebrewSplit.masterAndInspector` into the segmented candidate's own ideal
/// width with `.frame(minWidth:)`, so `ViewThatFits` is asking «is this pane
/// wide enough for the whole wide page» — `max(560, what the bar needs here)` —
/// and the columns read that answer instead of measuring the width again.
///
/// **What this asserts is that the two widths are one width**, per language,
/// found by sweeping the real page rather than by reading a constant. It does
/// *not* assert what that width is: the number is a fact about eight sets of
/// strings and the metrics of a segmented control, and pinning it here would be
/// a test of today's font rather than of the page's shape. What it does pin is
/// that the boundary exists, that it is inside the range a window can reach,
/// and that both facts turn over at it.
///
/// **And both shapes must really be reachable.** A page that never drew two
/// columns, or never drew the menu, would pass "they change together" by
/// drawing nothing that changes — so each end of the sweep is asserted outright.
@MainActor
final class ThePageReorganisesOnceTests: XCTestCase {

    /// Says brew is here and hands back two packages. The rows are not the
    /// subject — the master column's trailing edge is — but a list with nothing
    /// in it draws a sentence and no list at all, and then there is no column to
    /// measure.
    private final class BrewIsHere: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode(
                    [BrewPackage(name: "wget", version: "1.25.0", isCask: false),
                     BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)])
            default:
                return Data("[]".utf8)
            }
        }
    }

    private struct Shape {
        /// The bar drew the segmented switcher rather than the menu.
        let segmented: Bool
        /// The master list stops short of the pane's trailing edge, which is
        /// what a second column beside it looks like. nil when no list drew at
        /// all, so «there is no inspector» and «there is no page» stay apart.
        let twoColumns: Bool?
    }

    private func shape(at width: CGFloat) -> Shape {
        let transport = BrewIsHere()
        let mvm = ModuleViewModel(transport: transport)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 640, appearance: .aqua)
        mount.settle(20)
        let band: CGFloat = 48
        let segmented = mount.host.everyView(named: "SwiftUISegmentedControl")
            .map { $0.convert($0.bounds, to: mount.host) }
            .contains { $0.maxY <= band && $0.width > 0.5 }
        let list = mount.host.everyView
            .filter { $0.appKitClassName.contains("ListCoreScrollView") }
            .map { $0.convert($0.bounds, to: mount.host) }
            .first
        mount.drop()
        withExtendedLifetime(transport) {}
        return Shape(segmented: segmented, twoColumns: list.map { $0.maxX < width - 1.5 })
    }

    /// The pane the app opens at on this Mac, where the wide shape is what
    /// every language draws.
    private static let usualPane: CGFloat = 984
    /// The narrowest pane a person can reach — `SettingsWindow.swift` carries
    /// the three numbers behind it — and the bottom of the sweep.
    private static let narrowestPane: CGFloat = 540
    /// Above every language's boundary. It was 600, which cleared `ja`'s 572
    /// by 28 — and then the bar gained the reserved slot «Обновить всё» sits
    /// in (`upgradeAll`), which moved the boundary in the three languages
    /// whose switcher was already the widest: swept 2026-09-16, es 581 ·
    /// ru 593 · ja 599, the other five still at 560. Japanese sat one point
    /// under the old top, which is a sweep that passes by luck. The sweep has to end above the widest of the eight,
    /// or the failure it reports is «no boundary here» rather than the two
    /// boundaries it exists to compare.
    private static let topOfTheSweep: CGFloat = 660

    func testTheHeaderAndTheColumnsTurnOverAtOneWidthInEveryLanguage() {
        AppLanguage.each { language in
            let wide = shape(at: Self.usualPane)
            XCTAssertTrue(wide.segmented, """
                \(language.rawValue): the bar drew the menu at \(Self.usualPane) pt, the pane \
                the app opens — nothing below is a reading of a boundary
                """)
            XCTAssertEqual(wide.twoColumns, true, """
                \(language.rawValue): there is no inspector at \(Self.usualPane) pt, so the \
                sweep below has only one shape to find
                """)

            let narrow = shape(at: Self.narrowestPane)
            XCTAssertFalse(narrow.segmented, """
                \(language.rawValue): the bar still drew the segmented switcher at \
                \(Self.narrowestPane) pt, where the page is in its one-column shape — the two \
                facts are not the one fact this claims they are
                """)
            XCTAssertEqual(narrow.twoColumns, false, """
                \(language.rawValue): the inspector is still beside the list at \
                \(Self.narrowestPane) pt
                """)

            // The sweep: the first width at which each fact turns over.
            var headerTurns: CGFloat?
            var columnsTurn: CGFloat?
            for width in stride(from: Self.narrowestPane, through: Self.topOfTheSweep, by: 1) {
                let drawn = shape(at: width)
                if headerTurns == nil, drawn.segmented { headerTurns = width }
                if columnsTurn == nil, drawn.twoColumns == true { columnsTurn = width }
                if headerTurns != nil, columnsTurn != nil { break }
            }

            XCTAssertNotNil(headerTurns, """
                \(language.rawValue): the bar never took its segmented shape between \
                \(Self.narrowestPane) and \(Self.topOfTheSweep) pt, though it has it at \
                \(Self.usualPane)
                """)
            XCTAssertNotNil(columnsTurn, """
                \(language.rawValue): the inspector never appeared between \
                \(Self.narrowestPane) and \(Self.topOfTheSweep) pt
                """)
            guard let headerTurns, let columnsTurn else { return }
            XCTAssertEqual(headerTurns, columnsTurn, """
                \(language.rawValue): the switcher changes shape at \(headerTurns) pt and the \
                columns at \(columnsTurn) — \(abs(headerTurns - columnsTurn)) pt apart, so a \
                window dragged across that band reorganises the page twice
                """)
        }
    }
}
