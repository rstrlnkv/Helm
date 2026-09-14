import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Below `HomebrewSplit`'s threshold the page draws a list nobody can act on.**
///
/// Every action this module has — Uninstall, Upgrade, Install — is drawn by
/// `HomebrewSettingsPage.inspectorAction`, which only the *split* branch of
/// `managerBody` reaches. The other branch, `listArea(showsDesc: true)`, draws
/// rows and a description and no control at all, and it is the branch that runs
/// whenever the pane is narrower than 560 pt. Before this page became a master
/// list and an inspector the row carried its own button, so this is a capability
/// the change removed rather than a width nobody thought about.
///
/// **The band is reachable, and it is reachable by arithmetic rather than by
/// opinion.** `SettingsWindow` refuses a content width under 860 and lets the
/// sidebar be dragged to 320, so the narrowest pane a person can produce is
/// 860 − 320 = 540 pt — twenty points under the threshold, one drag of the
/// sidebar divider at the smallest window the app allows. The detail item's own
/// `minimumThickness` of 420 is the floor below that, and is what the band would
/// open out to if the window minimum ever fell. All four numbers are read out of
/// `Sources/HelmApp/SettingsWindow.swift` rather than copied here, so the day the
/// band closes this file fails and says so instead of passing over a page that
/// no longer has the problem.
///
/// **Measured against HEAD, 2026-09-14, three consecutive runs.** In the
/// installed segment the page draws a `ListCoreScrollView` at 540, 549 and
/// 559 pt — the rows are there — and **zero** `_FocusRingView`s at every one of
/// them; at 834 pt with the same package selected it draws exactly one, the
/// inspector's. In the updates segment the only ring at any narrow width is the
/// «Upgrade all» button above the list, and none inside it.
///
/// **Why runtime and not a source scan.** Which branch draws is a function of a
/// width, and the whole defect is that one branch has controls and the other
/// does not — a scan reading `HomebrewSettingsPage.swift` finds `Button(HbStr.
/// uninstall)` in the file and cannot say which widths reach it. It would also
/// go green the moment somebody wrote a second switch, which is the other half
/// of what this file is for: the count of actions the page draws is compared
/// against what `InspectorState.of` says the same packages offer, so a narrow
/// branch that offers an upgrade on a pinned formula is red even though it draws
/// «more» than HEAD does.
@MainActor
final class TheNarrowPaneCanStillActOnAPackageTests: XCTestCase {

    // MARK: - The fixture

    /// Answers the four queries the page puts on its way to drawing rows, and
    /// nothing else. Named at every construction; there is no default port here
    /// that could reach this Mac's own brew.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)
        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
        /// One upgradeable and one pinned, because the two must not be offered
        /// the same thing and that is where a second switch diverges first.
        static let node = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                          isCask: false)
        static let git = OutdatedPackage(name: "git", installed: "2.54.0", latest: "2.55.0",
                                         isCask: false, pinned: true)

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([Self.wget, Self.openssl])
            case .outdated: return try JSONEncoder().encode([Self.node, Self.git])
            // Answered, and answered empty: the description batch runs behind
            // every list refresh and an unanswered port is a refusal.
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    // MARK: - The band, read out of the window that decides it

    /// One integer assigned to `name` in `SettingsWindow.swift`, and a failure
    /// naming the file when there is not exactly one.
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
                window's own numbers have moved and the band below is being computed from a \
                pattern that no longer finds them
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

    /// The widths a person can actually put this page at and still be under the
    /// split: the narrowest pane the window allows, the widest that is still
    /// narrow, and one in between.
    ///
    /// Fails rather than skips when the band is empty. A band that has closed
    /// means this whole file is about a state nobody can reach any more, and a
    /// skip reads as a pass in a failures-only summary.
    private func narrowBand(file: StaticString = #filePath, line: UInt = #line) -> [CGFloat] {
        guard let contentMin = windowNumber(#"minSize = NSSize\(width: ([0-9.]+)"#,
                                            "the window's minimum content width"),
              let sidebarMax = windowNumber(#"sidebarMaximum: CGFloat = ([0-9.]+)"#,
                                            "the sidebar's maximum thickness"),
              let detailMin = windowNumber(#"detailItem\.minimumThickness = ([0-9.]+)"#,
                                           "the detail pane's minimum thickness")
        else { return [] }
        let split = threshold
        XCTAssertGreaterThan(split, 0, "no width in 200…1400 shows the inspector", file: file, line: line)
        // The pane is what is left of the smallest window when the sidebar is
        // dragged as wide as it goes, and never less than the pane's own floor.
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
        /// Every focus ring on the page — a control with a border, which is
        /// what all three of this module's actions are.
        let rings: [CGRect]
        /// The ones drawn on a row of the master list rather than above it;
        /// «Upgrade all» sits outside and must not be counted as a row's action.
        let onRows: [CGRect]
        let lists: [CGRect]
    }

    /// Mounts the page at `width` with `segment` showing, and reads what drew.
    ///
    /// Light, named: an unnamed appearance is a reading of whatever this Mac is
    /// set to at this hour (`RenderedInk`'s reason).
    private func draw(_ hb: HomebrewViewModel, _ mvm: ModuleViewModel,
                      at width: CGFloat, segment: HomebrewViewModel.Segment,
                      selecting id: String?) -> Reading {
        hb.segment = segment
        hb.select(id)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        mount.settle(25)
        let lists = mount.host.everyView
            .filter { $0.appKitClassName.contains("ListCoreScrollView") }
            .map { $0.convert($0.bounds, to: mount.host) }
        var rings: [CGRect] = []
        var onRows: [CGRect] = []
        for (view, ancestry) in mount.host.everyViewWithAncestry
        where view.appKitClassName == "_FocusRingView" {
            let frame = view.convert(view.bounds, to: mount.host)
            rings.append(frame)
            if ancestry.contains(where: { $0.appKitClassName.contains("ListCoreScrollView") }) {
                onRows.append(frame)
            }
        }
        mount.drop()
        return Reading(rings: rings, onRows: onRows, lists: lists)
    }

    private func loaded() async -> (HomebrewViewModel, ModuleViewModel, Cellar) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        await hb.refreshOutdated()
        return (hb, mvm, transport)
    }

    /// What `InspectorState.of` says a package offers — the one place that
    /// decides, and the thing the row has to agree with.
    private func action(_ hb: HomebrewViewModel, _ segment: HomebrewViewModel.Segment,
                        _ id: String) -> InspectorSubject.Action? {
        guard case let .package(subject) = InspectorState.of(
            segment: segment, selected: id, installed: hb.installed, outdated: hb.outdated,
            loadedOutdated: hb.loadedOutdated, hits: hb.searchHits, descriptions: hb.descriptions)
        else { return nil }
        return subject.action
    }

    // MARK: - The capability

    /// **A list you cannot act on, at every width the window can be dragged to.**
    func testThePageOffersAnActionAtEveryWidthUnderTheSplit() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard !band.isEmpty else { return }

        for width in band {
            let wide = draw(hb, mvm, at: width, segment: .installed, selecting: nil)
            // The subject before the absence: rows have to be there at all, or
            // "no action drew" is true of a page that drew nothing.
            XCTAssertEqual(wide.lists.count, 1, """
                no master list drew at \(width) pt, so nothing below is a reading of a page with \
                packages on it
                """)
            XCTAssertFalse(HomebrewSplit(availableWidth: width).showsInspector, """
                \(width) pt is not under the split after all — the band was computed from the \
                window's own numbers and one of them has moved
                """)
            XCTAssertGreaterThanOrEqual(wide.rings.count, 1, """
                at \(width) pt the Homebrew page draws \(hb.installed.count) packages and \
                \(wide.rings.count) controls. The pane can be this narrow — the window refuses to \
                be smaller than its own minimum and the sidebar drags to its own maximum — and at \
                this width `HomebrewSplit.showsInspector` is false, so `inspectorAction` is never \
                reached and there is no Uninstall, no Upgrade and no Install anywhere on the page.
                """)
        }
    }

    // MARK: - The agreement

    /// **And the narrow rows must offer what the inspector offers — including
    /// the package it offers nothing for.**
    ///
    /// Two outdated packages, one of them pinned. `InspectorState.of` answers
    /// `.upgrade` for one and `.pinned` for the other, so exactly one action may
    /// be drawn on the rows. A narrow branch that carried its own switch would
    /// draw two, and a narrow branch that draws none — which is HEAD — draws
    /// zero; both are this assertion.
    ///
    /// «Upgrade all» is a control on this segment too, above the list rather
    /// than on a row, which is why the reading is of the rings inside the list
    /// and its presence is asserted first.
    func testTheNarrowRowsOfferExactlyWhatTheInspectorWouldOffer() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard let width = band.first else { return }

        let offered = hb.outdated.filter { action(hb, .updates, $0.id) != .pinned }
        XCTAssertEqual(offered.count, 1, """
            the fixture is meant to hold one upgradeable package and one pinned one, and \
            `InspectorState.of` offers an action for \(offered.count) of \(hb.outdated.count) — \
            nothing below tells a missing action from a wrongly offered one
            """)

        let reading = draw(hb, mvm, at: width, segment: .updates, selecting: nil)
        XCTAssertEqual(reading.lists.count, 1, "no master list drew at \(width) pt")
        XCTAssertEqual(reading.rings.count - reading.onRows.count, 1, """
            \(reading.rings.count - reading.onRows.count) controls drew above the list at \
            \(width) pt where «Upgrade all» is the only one — the split between a row's own \
            action and the segment's is being read wrong and the count below means nothing
            """)
        XCTAssertEqual(reading.onRows.count, offered.count, """
            at \(width) pt the updates list draws \(reading.onRows.count) actions on its rows \
            where `InspectorState.of` offers \(offered.count) for the same two packages. Zero is \
            the single-column branch drawing no action at all; two is a narrow branch that \
            decided for itself and offered an upgrade for a pinned formula, which `brew upgrade` \
            answers with «…is pinned».
            """)
    }

    /// **The verb, not only the button.**
    ///
    /// The action a row offers has to be the action the inspector offers for the
    /// same package above the threshold. A rendered SwiftUI button carries no
    /// readable title — `NSHostingView` builds no accessibility tree until a
    /// client connects, measured here as zero children under the host — so the
    /// verb is identified by the width the word gives a bordered button, against
    /// `ControlMetrics`' own measurement of each of the three.
    ///
    /// **The language is chosen by measurement, and that is not a nicety.** In
    /// English «Uninstall» and «Upgrade» are both 77 pt and in Chinese all three
    /// are 50, so this check is blind in two of the eight and would pass over a
    /// row offering the wrong verb. The language used is the first one whose six
    /// candidate widths — three verbs at both control sizes — are all more than
    /// 4 pt apart; if no language separates them the test fails rather than
    /// passing on a reading that cannot tell them apart.
    func testTheActionOnANarrowRowIsTheOneTheInspectorOffersAbove() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard let narrow = band.first else { return }
        let wide = threshold + 274      // the pane at the window's default width

        guard let (language, widths) = tellableApartLanguage() else {
            return XCTFail("""
                no language spells Uninstall, Upgrade and Install at widths this reading can tell \
                apart, so it cannot say which verb a button carries — identify the action some \
                other way rather than leaving a check that cannot fail
                """)
        }

        AppLanguage.only(language) {
            let selected = Cellar.wget.id
            guard let expected = action(hb, .installed, selected) else {
                return XCTFail("the fixture's own package is not in the installed list")
            }
            XCTAssertEqual(expected, .uninstall, "precondition: the inspector's own answer")

            let above = draw(hb, mvm, at: wide, segment: .installed, selecting: selected)
            XCTAssertEqual(above.rings.count, 1, """
                \(above.rings.count) controls at \(wide) pt where the inspector's action is the \
                only one — the reading below has nothing known-good to compare against
                """)
            guard let inspector = above.rings.first else { return }
            XCTAssertEqual(verb(ofWidth: inspector.width, widths), expected, """
                the inspector's own button measures \(inspector.width) pt in \(language), which \
                this reading does not call \(expected) — the identification is wrong before any \
                row is looked at
                """)

            let below = draw(hb, mvm, at: narrow, segment: .installed, selecting: selected)
            guard let row = below.rings.first else {
                return XCTFail("""
                    at \(narrow) pt the page draws no action for \(Cellar.wget.name), where the \
                    same package selected at \(wide) pt is offered \(expected). One fact, two \
                    placements — and at this width there is no placement at all.
                    """)
            }
            XCTAssertEqual(verb(ofWidth: row.width, widths), expected, """
                the action drawn for \(Cellar.wget.name) at \(narrow) pt measures \(row.width) pt, \
                which is not \(expected) — the row and the inspector disagree about what this \
                package offers, which is two switches where the design says one
                """)
        }
    }

    /// The three verbs' button widths in a language where all six are separable.
    private func tellableApartLanguage() -> (AppLanguage, [InspectorSubject.Action: [CGFloat]])? {
        var found: (AppLanguage, [InspectorSubject.Action: [CGFloat]])?
        AppLanguage.each { language in
            guard found == nil else { return }
            let table: [InspectorSubject.Action: [CGFloat]] = [
                .uninstall: [ControlMetrics.button(HbStr.uninstall),
                             ControlMetrics.smallButton(HbStr.uninstall)],
                .upgrade: [ControlMetrics.button(HbStr.upgrade),
                           ControlMetrics.smallButton(HbStr.upgrade)],
                .install: [ControlMetrics.button(HbStr.install),
                           ControlMetrics.smallButton(HbStr.install)],
            ]
            let all = table.values.flatMap { $0 }
            if all.allSatisfy({ candidate in all.filter { abs($0 - candidate) < 4 }.count == 1 }) {
                found = (language, table)
            }
        }
        return found
    }

    /// Which verb a button of this width carries, or nil when it is none of
    /// them or more than one of them.
    ///
    /// A focus ring is drawn half a point inside the control's own width, so the
    /// tolerance is 1.5 against a separation of more than 4.
    private func verb(ofWidth width: CGFloat,
                      _ widths: [InspectorSubject.Action: [CGFloat]]) -> InspectorSubject.Action? {
        let hits = widths.filter { $0.value.contains { abs($0 - width) <= 1.5 } }
        return hits.count == 1 ? hits.first?.key : nil
    }
}
