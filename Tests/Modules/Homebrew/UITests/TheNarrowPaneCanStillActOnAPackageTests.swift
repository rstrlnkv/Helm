import XCTest
import AppKit
import SwiftUI
import Foundation
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Below `HomebrewSplit`'s threshold, selecting a package must still offer
/// its action.**
///
/// Narrow used to mean "no inspector and no action anywhere" — the defect this
/// file was first written against. The repair that followed put the action back
/// on the *row*, which meant two switches deciding what a package offers and
/// one of them (`testAPinnedRowDrawsThePinnedBadgeOnlyOnce`, below) catching the
/// two disagreeing about a pinned formula's badge. That repair is withdrawn.
///
/// **The shape now: below the threshold, a screen, not a row.** Selecting a
/// package replaces the list with `HomebrewSettingsPage.packageDetail` — the
/// same builder the wide layout puts beside the list — behind a `backBar` that
/// returns to it. There is exactly one place an action is ever drawn, at either
/// width, which is what this file now reads for.
///
/// **The band is reachable, and it is reachable by arithmetic rather than by
/// opinion.** `SettingsWindow` refuses a content width under 860 and lets the
/// sidebar be dragged to 320, so the narrowest pane a person can produce is
/// 860 − 320 = 540 pt — twenty points under the threshold, one drag of the
/// sidebar divider at the smallest window the app allows. The detail item's own
/// `minimumThickness` of 420 is the floor below that, and is what the band would
/// open out to if the window minimum ever fell. All three numbers are read out
/// of `Sources/HelmApp/SettingsWindow.swift` rather than copied here, so the day
/// the band closes this file fails and says so instead of passing over a page
/// that no longer has the problem.
///
/// **Why runtime and not a source scan.** Which screen draws is a function of a
/// width and a selection, and the whole defect is that one branch could offer
/// nothing, or two branches could each decide on their own — a scan reading
/// `HomebrewSettingsPage.swift` finds `Button(HbStr.uninstall)` in the file and
/// cannot say which widths and which selections reach it.
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
        /// Every focus ring on the page — a bordered control, which is what
        /// every action here is, and what `backBar`'s own glyph button is too.
        let rings: [CGRect]
        let lists: Int
    }

    /// Mounts the page at `width` with `segment` showing, selects `id`, and
    /// reads what drew.
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
            .filter { $0.appKitClassName.contains("ListCoreScrollView") }.count
        let rings = mount.host.everyView(named: "_FocusRingView")
            .map { $0.convert($0.bounds, to: mount.host) }
        mount.drop()
        return Reading(rings: rings, lists: lists)
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
    /// decides, and the thing the narrow screen has to agree with.
    private func action(_ hb: HomebrewViewModel, _ segment: HomebrewViewModel.Segment,
                        _ id: String) -> InspectorSubject.Action? {
        guard case let .package(subject) = InspectorState.of(
            segment: segment, selected: id, installed: hb.installed, outdated: hb.outdated,
            loadedOutdated: hb.loadedOutdated, hits: hb.searchHits, descriptions: hb.descriptions)
        else { return nil }
        return subject.action
    }

    // MARK: - The screen

    /// **A selection replaces the list with a screen carrying its action.**
    func testANarrowSelectionShowsThePackageScreenAndNoList() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard let width = band.first else { return }

        let none = draw(hb, mvm, at: width, segment: .installed, selecting: nil)
        XCTAssertEqual(none.lists, 1, "no master list drew at \(width) pt with nothing selected")

        let selected = draw(hb, mvm, at: width, segment: .installed, selecting: Cellar.wget.id)
        XCTAssertEqual(selected.lists, 0, """
            the master list still drew at \(width) pt with \(Cellar.wget.name) selected — a \
            selection at this width should replace the list with the package screen, not sit \
            beside a list that has no room for a second column
            """)
        XCTAssertGreaterThanOrEqual(selected.rings.count, 1, """
            \(selected.rings.count) controls drew at \(width) pt with \(Cellar.wget.name) selected \
            — the package screen offers no action, `backBar` included, where the fixture's own \
            package is offered Uninstall
            """)
    }

    // MARK: - The agreement

    /// **The verb, not only the button — and it has to be the wide inspector's
    /// own verb, because both come from one builder.**
    ///
    /// A rendered SwiftUI button carries no readable title — `NSHostingView`
    /// builds no accessibility tree until a client connects, measured here as
    /// zero children under the host — so the verb is identified by the width the
    /// word gives a bordered button, against `ControlMetrics`' own measurement
    /// of each of the three.
    ///
    /// **The language is chosen by measurement, and that is not a nicety.** In
    /// English «Uninstall» and «Upgrade» are both 77 pt and in Chinese all three
    /// are 50, so this check is blind in two of the eight and would pass over a
    /// screen offering the wrong verb. The language used is the first one whose
    /// six candidate widths — three verbs at both control sizes — are all more
    /// than 4 pt apart; if no language separates them the test fails rather than
    /// passing on a reading that cannot tell them apart.
    func testTheNarrowScreenOffersTheSameActionAsTheWideInspector() async {
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
            let aboveVerbs = above.rings.compactMap { verb(ofWidth: $0.width, widths) }
            XCTAssertEqual(aboveVerbs, [expected], """
                \(aboveVerbs) is what the wide inspector's own rings measure as, at \(wide) pt in \
                \(language), where the only offer should be \(expected) — the reading below has \
                nothing known-good to compare against
                """)

            let below = draw(hb, mvm, at: narrow, segment: .installed, selecting: selected)
            let belowVerbs = below.rings.compactMap { verb(ofWidth: $0.width, widths) }
            XCTAssertEqual(belowVerbs, [expected], """
                the narrow screen for \(Cellar.wget.name) at \(narrow) pt measures \(belowVerbs) \
                where the wide inspector for the same package measures \(aboveVerbs) — both read \
                `packageDetail`, so a disagreement here means two builders exist where the design \
                says one
                """)
        }
    }

    // MARK: - The resize invariant

    /// **Pushed into a package narrow, then widened past the split, lands
    /// beside the list — not on nothing.**
    ///
    /// Selection lives in `HomebrewViewModel`, per segment, and neither branch
    /// of `managerBody` clears it — so this falls out of state rather than
    /// needing anything held for it. Same fixture, same `hb`, mounted twice.
    func testWideningPastTheSplitWithASelectionLandsBesideTheList() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard let narrow = band.first else { return }
        let wide = threshold + 274

        let selected = Cellar.wget.id
        let pushed = draw(hb, mvm, at: narrow, segment: .installed, selecting: selected)
        XCTAssertEqual(pushed.lists, 0, "precondition: narrow with a selection shows no list")

        // Nothing re-selects here — the same `hb` carries the selection over,
        // the way widening the real window would.
        XCTAssertEqual(hb.selected, selected, "the selection did not survive the narrow reading")
        let widened = draw(hb, mvm, at: wide, segment: .installed, selecting: hb.selected)
        XCTAssertEqual(widened.lists, 1, """
            widening to \(wide) pt with \(Cellar.wget.name) still selected drew \(widened.lists) \
            master lists — the wide branch should show the list beside the package, not drop it
            """)
        XCTAssertGreaterThanOrEqual(widened.rings.count, 1, """
            widening to \(wide) pt with a selection carried over drew no controls at all — landing \
            "on nothing" is exactly the failure this invariant is against
            """)
    }

    // MARK: - Back

    /// **The button's own action, read from the source it is defined in.**
    ///
    /// A rendered SwiftUI button carries no closure a test can call, so the
    /// wiring is read the way `narrowBand` reads the window's numbers: as text,
    /// inside the one computed property that defines it, rather than assumed.
    private func backBarCallsSelectNil(file: StaticString = #filePath,
                                       line: UInt = #line) -> Bool {
        guard let text = try? RepoSource.text(of: "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift")
        else {
            XCTFail("HomebrewSettingsPage.swift could not be read", file: file, line: line)
            return false
        }
        guard let range = text.range(of: "private var backBar: some View {"),
              let end = text.range(of: "\n    }", range: range.upperBound..<text.endIndex)
        else {
            XCTFail("backBar's own declaration could not be found in the source", file: file, line: line)
            return false
        }
        return text[range.upperBound..<end.lowerBound].contains("hb.select(nil)")
    }

    /// **Back is `select(nil)`, and `select(nil)` is what returns the list.**
    ///
    /// Two halves: the source read above says what `backBar`'s press does, and
    /// this reads what that call produces — a selection is not held anywhere
    /// `backBar` would have to reach into and clear by hand.
    func testBackClearsTheSelectionAndTheListReturns() async {
        XCTAssertTrue(backBarCallsSelectNil(), """
            backBar no longer calls select(nil) — the runtime half of this test would then be \
            reading a screen that presses a button doing something else
            """)

        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard let width = band.first else { return }

        let pushed = draw(hb, mvm, at: width, segment: .installed, selecting: Cellar.wget.id)
        XCTAssertEqual(pushed.lists, 0, "precondition: a selection shows the package screen")

        hb.select(nil)   // what backBar's press does
        let backed = draw(hb, mvm, at: width, segment: .installed, selecting: hb.selected)
        XCTAssertEqual(backed.lists, 1, "select(nil) did not bring the list back at \(width) pt")
        XCTAssertNil(hb.selected, "select(nil) left a selection in place")
    }

    // MARK: - The pinned package's own badge

    /// **A pinned package must not say «Pinned» twice.**
    ///
    /// `packageDetail` draws the badge once, from `inspectorAction`'s `.pinned`
    /// case — the row that used to carry its own copy alongside it is gone, and
    /// with it the condition (`action.action != .pinned`) that used to be all
    /// that stood between one badge and two. What this now guards is the single
    /// builder itself: nothing here should ever draw the badge from two places
    /// again, at either width, because there is supposed to be only one.
    func testAPinnedPackagesScreenDrawsThePinnedBadgeOnlyOnce() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let band = narrowBand()
        guard let width = band.first else { return }
        hb.segment = .updates
        hb.select(Cellar.git.id)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        mount.settle(25)
        let capsules = capsuleLayers(on: mount.host)
        mount.drop()
        XCTAssertEqual(capsules.count, 1, """
            the narrow screen for \(Cellar.git.name) draws \(capsules.count) capsule-shaped layers \
            (\(capsules)) where the fixture's one pinned package should draw its «Pinned» badge \
            exactly once
            """)
    }

    /// CALayer shapes whose corner radius is half their height — the signature a
    /// SwiftUI `Capsule` fill leaves, which is the only shape `HelmBadge` draws
    /// and the only capsule this page has any other reason to draw.
    private func capsuleLayers(on view: NSView) -> [CGRect] {
        guard let root = view.layer else { return [] }
        var out: [CGRect] = []
        func walk(_ layer: CALayer) {
            let frame = root.convert(layer.bounds, from: layer)
            if layer.cornerRadius > 1, abs(layer.cornerRadius - frame.height / 2) < 0.6 {
                out.append(frame)
            }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(root)
        return out
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
    /// them or more than one of them — which is also what a `backBar` glyph
    /// ring's width answers, since it matches no verb's measured width.
    ///
    /// A focus ring is drawn half a point inside the control's own width, so the
    /// tolerance is 1.5 against a separation of more than 4.
    private func verb(ofWidth width: CGFloat,
                      _ widths: [InspectorSubject.Action: [CGFloat]]) -> InspectorSubject.Action? {
        let hits = widths.filter { $0.value.contains { abs($0 - width) <= 1.5 } }
        return hits.count == 1 ? hits.first?.key : nil
    }
}
