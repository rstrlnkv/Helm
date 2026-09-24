import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The wider the window, the more of a row's title a person sees — which is
/// the opposite of what this page did.**
///
/// The master column was `maxWidth: 310` at every pane. Measured 2026-09-16: a
/// row's content was **254 pt** at the 984 pt pane the app draws and **484 pt**
/// at 540, where the pane is under `HomebrewSplit`'s threshold and the list has
/// it to itself. This Mac's own `brew doctor` titles are 258.3, 546.9 and 327.8
/// pt wide, so at the wide window all three were truncated and at the narrow one
/// only the long one — while the inspector beside it was 649 pt wide and drew
/// into 444 of them.
///
/// Two halves, and both are needed. The arithmetic says the column grows and
/// that the inspector keeps its bounded reading column; the rendering says the
/// page really draws it that way, because a `frame` modifier is a request and
/// not a measurement.
@MainActor
final class TheMasterColumnTakesAShareOfAWidePaneTests: XCTestCase {

    private static let threshold: CGFloat = 560
    private static let panes: [CGFloat] = [560, 760, 984]

    // MARK: - The rule

    /// **At the threshold the divider is what it was**, which is not a
    /// nicety: `TheSplitThresholdFitsThePageItGatesTests` measured the split
    /// layout's 521 pt floor against a master whose stack left the divider at
    /// 322 (310 pt wide plus the 12 pt of spacing the stack used to spend
    /// after it), and that measurement only still describes this page while
    /// the divider has not moved. It has not: `masterWidth` itself grew from
    /// 310 to 322 the day the list stopped falling short of the divider
    /// (`TheGapBesideTheListClosesOnlyThereTests`), because the 12 pt the
    /// stack used to spend on that side is handed to the master now instead —
    /// at the floor exactly as much as in between, which is what keeps the
    /// divider from moving with it.
    func testTheNarrowEndsDividerIsUnchanged() {
        XCTAssertEqual(HomebrewSplit(availableWidth: Self.threshold).masterWidth, 322, """
            the master column is \(HomebrewSplit(availableWidth: Self.threshold).masterWidth) pt \
            at the split's own threshold, where it should be 322 — 310, the floor this layout was \
            measured against, plus the 12 pt the list-side gutter used to spend and now hands to \
            the master instead
            """)
    }

    /// It grows, and it grows by the time the app's own pane is reached — a rule
    /// that only pays out at widths nobody opens is a rule that changed nothing.
    func testItGrowsAndNeverShrinks() {
        var previous: CGFloat = 0
        for width in stride(from: Self.threshold, through: 1600, by: 1) {
            let master = HomebrewSplit(availableWidth: width).masterWidth
            XCTAssertGreaterThanOrEqual(master, previous, """
                the master column narrowed from \(previous) to \(master) as the pane grew to \
                \(width) — which is the defect this rule replaces, said the other way round
                """)
            // The reading column's own ceiling, plus the 12 pt the list-side
            // gutter hands the master at every width including this one — not
            // slack the master is spending, the gap it used to fall short of
            // (`TheGapBesideTheListClosesOnlyThereTests`).
            XCTAssertLessThanOrEqual(master, HelmLayout.readingColumn + HelmSpace.s5, """
                the master column reached \(master) pt at \(width), past the reading column and \
                the list-side gutter it was handed — a list of package names is not prose and \
                does not want the whole window
                """)
            previous = master
        }
        XCTAssertGreaterThan(HomebrewSplit(availableWidth: 984).masterWidth, 322, """
            the column is still 322 pt — its own floor — at the pane the app actually draws, so \
            nothing a person sees has changed
            """)
    }

    /// **`masterWidth` is exactly 12 pt above the formula it replaced, at
    /// every width, not only between its floor and its ceiling.** The first
    /// version of the gap fix added the list-side gutter's 12 pt to the
    /// *unclamped* share alone, so the floor stayed 310 and the ceiling
    /// stayed 444 — which moves the divider, and everything past it, by up to
    /// 12 pt at every width outside that one band (caught by a reviewer's own
    /// probe of the formula, not by a test in this tree, since the one guard
    /// mounting the real page had picked a width inside the safe band). This
    /// is the structural fact the case above and
    /// `TheGapBesideTheListClosesOnlyThereTests.testTheDividerDoesNotMoveAcrossThePane`
    /// both rest on: the pane-width figures this file and
    /// `TheSplitThresholdFitsThePageItGatesTests` carry for the split
    /// layout's own floor predate the gap fix and are not re-measured here —
    /// this proves they do not need to be, because the total width spent
    /// before the inspector's own column starts is identical to what the
    /// pre-fix formula spent, for every width swept.
    func testMasterWidthIsTwelveAboveThePreFixFormulaEverywhere() {
        for width: CGFloat in stride(from: CGFloat(0), through: 1600, by: 1) {
            let preFixGutter: CGFloat = HelmSpace.s5 * 2 + 1
            let inspector = HelmLayout.readingColumn + HelmSpace.s5 * 2
            let preFixMaster = min(max(310, width - preFixGutter - inspector), HelmLayout.readingColumn)
            let master = HomebrewSplit(availableWidth: width).masterWidth
            XCTAssertEqual(master, preFixMaster + HelmSpace.s5, accuracy: 0.001, """
                at \(width) pt masterWidth answers \(master), not \(preFixMaster) + 12 — the \
                divider has moved from where the pre-fix formula put it
                """)
        }
    }

    /// **And the inspector keeps its bounded column.** The slack the master
    /// takes is only the slack the inspector was wasting: wherever the master
    /// has grown past its floor, what is left over still covers
    /// `helmInspectorColumn`'s cap and the padding around it.
    func testTheInspectorKeepsItsReadingColumn() {
        let needed = HelmLayout.readingColumn + HelmSpace.s5 * 2
        for width in stride(from: Self.threshold, through: 1600, by: 1) {
            let master = HomebrewSplit(availableWidth: width).masterWidth
            // 322: the floor `masterWidth` now returns (310 plus the list-side
            // gutter's 12 pt, handed to the master even at the floor) — below
            // it the master is pinned and this reading is not about slack.
            guard master > 322 else { continue }
            // The divider and the inspector's own leading padding —
            // `managerBody`'s `HStack(spacing: 0)` spends nothing on the
            // list's side of the gutter any more
            // (`TheGapBesideTheListClosesOnlyThereTests`).
            let left = width - master - (HelmSpace.s5 + 1)
            XCTAssertGreaterThanOrEqual(left, needed, """
                at \(width) pt the master takes \(master) and leaves the inspector \(left), \
                where its bounded column and padding need \(needed) — the column the master \
                grew into was not slack
                """)
        }
    }

    // MARK: - What the page draws

    private final class TwoPackages: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)
        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([Self.wget, Self.openssl])
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            default:
                return Data()
            }
        }
    }

    /// The master list's own scroll view, in the pane's coordinates — the same
    /// view `TheSplitThresholdFitsThePageItGatesTests` measures the columns by.
    private func masterList(at width: CGFloat) async -> CGRect? {
        let transport = TwoPackages()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 620, appearance: .aqua)
        mount.settle(20)
        let frame = mount.host.everyView
            .filter { $0.appKitClassName.contains("ListCoreScrollView") }
            .map { $0.convert($0.bounds, to: mount.host) }
            .first
        mount.drop()
        withExtendedLifetime(transport) {}
        return frame
    }

    /// **Measured at the three widths, and the reading has to move.** Asserted
    /// as "wider at 984 than at 760" rather than against a literal: a literal
    /// here would be an assertion against the rule's own arithmetic, which the
    /// three cases above already hold.
    func testTheDrawnColumnWidensWithThePane() async {
        var drawn: [CGFloat: CGFloat] = [:]
        for pane in Self.panes {
            guard let frame = await masterList(at: pane) else {
                return XCTFail("no master list drew at \(pane) pt, so nothing was measured")
            }
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "the master column begins at \(frame.minX)")
            drawn[pane] = frame.width
        }
        XCTAssertGreaterThan(drawn[984] ?? 0, drawn[760] ?? 0, """
            the master list is \(drawn[984] ?? 0) pt wide at a 984 pt pane and \
            \(drawn[760] ?? 0) at 760 — the extra width still all goes to the inspector, so a \
            finding's title is no more readable in a big window than in a small one
            """)
        // **And the gain is one a person can read.** The old column drew a
        // 286 pt list at this pane — 254 pt of content once the row's own insets
        // are paid — and two of this Mac's three `brew doctor` titles are wider
        // than that. A floor of 380 here is 94 pt above what was shipping and
        // below the 420 measured after the change, so it is a claim about the
        // outcome rather than a restatement of the arithmetic.
        XCTAssertGreaterThanOrEqual(drawn[984] ?? 0, 380, """
            the master list is only \(drawn[984] ?? 0) pt wide at the pane the app draws, where \
            the column it replaces was 286 — the rule fires but gains nothing legible
            """)
    }
}
