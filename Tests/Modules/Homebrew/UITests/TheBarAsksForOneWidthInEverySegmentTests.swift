import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **«Обновить всё» lives in the bar, and the bar must not change width when
/// the segment does.**
///
/// `headerBar` folds `HomebrewSplit.masterAndInspector` into the segmented
/// candidate's own ideal width, so what the bar asks for is what decides
/// whether the page draws two columns at all — that is the whole point of
/// `ThePageReorganisesOnceTests`, which proves the two boundaries are one.
/// A control drawn in one segment and not the others would make that one
/// boundary four, and the segment it moved for is Обновления: a Russian window
/// in the band would show the inspector on Установленные and lose it the
/// moment somebody clicked the tab whose rows are things to act on.
///
/// So the button is *reserved* rather than conditional — both branches of
/// `upgradeAll` build the same control, and only its visibility differs. This
/// reads the page back and asserts the reservation really happened: the bar's
/// controls end at the same x in all four segments, including the three where
/// the button is not drawn at all.
///
/// **It is measured on the real page, not asserted about the source.** A
/// `.hidden()` that stopped reserving space — swapped for `if offered`, or for
/// an `opacity` on a view that was never laid out — compiles, reads the same,
/// and is invisible to any scan.
@MainActor
final class TheBarAsksForOneWidthInEverySegmentTests: XCTestCase {

    /// The pane the app draws on this Mac, wide enough that both shapes of the
    /// page are available and the bar is under no pressure — what is being
    /// compared is what the bar *asks* for, not what it was squeezed to.
    private static let usualPane: CGFloat = 984

    /// Says brew is here, hands back one installed package and one outdated
    /// one. Обновления needs a non-empty list for the button to be offered at
    /// all: with nothing to upgrade the control is hidden in that segment too,
    /// and the comparison would hold over a page that never draws it.
    private final class Cellar: EngineTransport, @unchecked Sendable {
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
                     BrewPackage(name: "node", version: "26.8.2", isCask: false)])
            case .outdated:
                return try JSONEncoder().encode(
                    [OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                     isCask: false, pinned: false)])
            default:
                return Data("[]".utf8)
            }
        }
    }

    /// The narrowest pane a person can reach, and the bottom of the sweep —
    /// `SettingsWindow.swift` carries the three numbers behind it.
    private static let narrowestPane: CGFloat = 540
    /// Above every language's boundary with the reserved slot in the bar:
    /// swept 2026-09-16 on the real page, en · zh · fr · de · pt 560 · es 581 ·
    /// ru 593 · ja 599.
    private static let topOfTheSweep: CGFloat = 640

    /// **Whether the bar drew the segmented switcher at this width in this
    /// segment** — which is `ViewThatFits`' answer to «is this pane wide enough
    /// for the whole wide page», and therefore the thing that must not depend
    /// on the segment.
    ///
    /// Read the way `ThePageReorganisesOnceTests` reads it, off the same band
    /// and the same SwiftUI class: the right *edge* of the bar is no reading at
    /// all, because a `Spacer(minLength: 0)` pins the trailing controls to the
    /// inset whatever is beside them — measured, a bar with the slot deleted
    /// ends at exactly the same x as one with it, so an edge comparison passes
    /// over the defect it was written for.
    private func drewSegments(_ hb: HomebrewViewModel, _ mvm: ModuleViewModel,
                              segment: HomebrewViewModel.Segment, at width: CGFloat) -> Bool {
        hb.segment = segment
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 640, appearance: .aqua)
        mount.settle(20)
        let band: CGFloat = 48
        let drew = mount.host.everyView(named: "SwiftUISegmentedControl")
            .map { $0.convert($0.bounds, to: mount.host) }
            .contains { $0.maxY <= band && $0.width > 0.5 }
        mount.drop()
        return drew
    }

    /// Russian, because the picker is at its widest there bar Japanese and the
    /// button's word is near the middle of the eight — the boundary is inside
    /// the sweep and well clear of both ends. The language is named rather than
    /// read from the Mac: this one runs in Russian, so a bare assertion would
    /// be a reading of the machine.
    func testTheBoundaryIsOneWidthWhicheverSegmentIsShowing() async {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        await hb.refreshOutdated()

        // Assert the subject before the comparison: Обновления must really be
        // offering the button, or every segment hides it and "one boundary" is
        // a statement about a control that is never drawn.
        XCTAssertFalse(hb.outdated.isEmpty,
                       "the fixture leaves nothing to upgrade, so the bar never offers the button "
                       + "and the sweep below compares four identical empty slots")

        AppLanguage.only(.ru) {
            var boundary: [HomebrewViewModel.Segment: CGFloat] = [:]
            for segment in HomebrewViewModel.Segment.allCases {
                XCTAssertFalse(drewSegments(hb, mvm, segment: segment, at: Self.narrowestPane), """
                    \(segment): the bar took its segmented shape already at \
                    \(Self.narrowestPane) pt, so the sweep has no boundary to find
                    """)
                for width in stride(from: Self.narrowestPane, through: Self.topOfTheSweep, by: 1)
                where drewSegments(hb, mvm, segment: segment, at: width) {
                    boundary[segment] = width
                    break
                }
                XCTAssertNotNil(boundary[segment], """
                    \(segment): the bar never took its segmented shape between \
                    \(Self.narrowestPane) and \(Self.topOfTheSweep) pt
                    """)
            }

            guard let reference = boundary[.installed] else { return }
            for (segment, width) in boundary {
                XCTAssertEqual(width, reference, accuracy: 0.5, """
                    the page turns over at \(width) pt on \(segment) and at \(reference) pt on \
                    Установленные, so the bar's width follows the segment. `headerBar` puts that \
                    width into the question `ViewThatFits` answers and the columns read that \
                    answer, so the page then has one boundary per segment — and the pane that \
                    loses its inspector is whichever one the person clicks
                    """)
            }
        }

        withExtendedLifetime(transport) {}
    }
}
