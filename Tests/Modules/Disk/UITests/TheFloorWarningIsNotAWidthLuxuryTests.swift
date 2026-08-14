import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Which sentence the header draws about the tree beside it, and at what width.
///
/// One threshold used to answer for all three. `DiskLayout.showsScanStatement` is
/// 800 pt of pane, measured for the bar carrying «N files in M s» — and the app's
/// own detail pane is 610 at `contentMinSize` and 645 with the default sidebar.
/// So at the width most people use, a **stopped** tree was drawn in full with
/// nothing saying that every folder figure in it is a floor, and a tree restored
/// from yesterday was indistinguishable from one measured a second ago. The
/// `stoppedHint` that explains it hangs on that `Text`, so a screen reader lost it
/// with the rest.
///
/// `StoppedStatementWidthTests` cannot see this: it holds the string's width
/// budget in eight languages, which is a check about truncation, and below the
/// threshold the line is *absent* rather than truncated.
///
/// The two warnings are not in the width budget any more. The cosmetic one still
/// is: it is the widest of the three and the only one nobody needs.
@MainActor
final class TheFloorWarningIsNotAWidthLuxuryTests: XCTestCase {

    /// The pane at `contentMinSize`, at the default window with the sidebar, at
    /// the measured threshold either side, and wide.
    private static let widths: [CGFloat] = [400, 610, 645, 744, 799, 800, 810, 1400]

    // MARK: - The rule

    func testAStoppedWalkSaysSoAtEveryWidth() {
        for width in Self.widths {
            XCTAssertEqual(DiskLayout(availableWidth: width)
                .statement(stopped: true, restored: false, hasResult: true), .stopped, """
                at \(width) pt of pane a stopped tree is drawn with every folder figure a floor \
                and nothing on screen saying so.
                """)
        }
    }

    func testARestoredTreeSaysWhenAtEveryWidth() {
        for width in Self.widths {
            XCTAssertEqual(DiskLayout(availableWidth: width)
                .statement(stopped: false, restored: true, hasResult: true), .measured, """
                at \(width) pt of pane yesterday's map is indistinguishable from one measured a \
                second ago.
                """)
        }
    }

    /// The cosmetic one keeps its budget: it is the widest of the three, and the
    /// only one that says nothing about whether the figures can be trusted.
    func testTheFileCountKeepsItsWidthBudget() {
        for width in Self.widths {
            let expected: DiskLayout.ScanStatement? = width >= 800 ? .scanned : nil
            XCTAssertEqual(DiskLayout(availableWidth: width)
                .statement(stopped: false, restored: false, hasResult: true), expected,
                           "at \(width) pt of pane")
        }
    }

    /// Stopped outranks restored: it is the only one of the three that makes the
    /// sizes beside it untrue as totals.
    func testAStoppedRescanOfARestoredTreeSaysStopped() {
        XCTAssertEqual(DiskLayout(availableWidth: 1400)
            .statement(stopped: true, restored: true, hasResult: true), .stopped)
    }

    /// No tree, no sentence about one — at any width.
    func testNothingIsSaidAboutATreeThatIsNotThere() {
        for width in Self.widths {
            XCTAssertNil(DiskLayout(availableWidth: width)
                .statement(stopped: true, restored: true, hasResult: false),
                         "at \(width) pt of pane")
        }
    }

    // MARK: - And it is drawn

    /// The control, and it comes first: at the wide pane the statement has always
    /// been drawn, so the two headers must read differently there. A reading that
    /// could not tell them apart would be about the instrument rather than about
    /// the page.
    ///
    /// Not «greater»: at 810 pt the finished tree draws «263 144 files in 12 s»,
    /// which is a great deal more ink than the one word «Stopped».
    func testTheInstrumentTellsTheTwoHeadersApartAtTheWidePane() async throws {
        for appearance in RenderedInk.bothAppearances {
            let plain = try await headerInk(stopped: false, width: 810, appearance: appearance)
            let stopped = try await headerInk(stopped: true, width: 810, appearance: appearance)

            XCTAssertNotEqual(stopped, plain,
                              "the header band reads the same in \(RenderedInk.label(of: appearance)) "
                              + "for two trees that say different things about themselves")
        }
    }

    /// **The measurement this file exists for.** At the pane the app opens at its
    /// own minimum, a stopped walk draws a word the finished walk does not — the
    /// finished one having nothing to say at that width, which is right.
    ///
    /// Before the repair the two readings were equal *to the byte* in both
    /// appearances (916 474 and 1 004 237), which is what «the warning is not
    /// drawn» looks like from here.
    func testTheWarningIsDrawnAtTheNarrowPane() async throws {
        for appearance in RenderedInk.bothAppearances {
            let plain = try await headerInk(stopped: false, width: 610, appearance: appearance)
            let stopped = try await headerInk(stopped: true, width: 610, appearance: appearance)

            XCTAssertGreaterThan(stopped, plain, """
                at 610 pt of pane, in \(RenderedInk.label(of: appearance)), a stopped walk drew a \
                header identical to a finished one: the one line saying the sizes below are \
                floors is behind a width budget measured for a different sentence.
                """)
        }
    }

    /// The header band of the real page, with a tree the walk finished or one it
    /// did not.
    private func headerInk(stopped: Bool, width: CGFloat,
                           appearance: NSAppearance.Name) async throws -> Int {
        let transport = HeldTransport()
        let vm = ModuleViewModel(transport: transport)
        let dvm = DiskViewModel(vm: vm, store: ScanStore(directory: scratchDirectory("disk-stmt")))
        let mount = MountedRender(DiskResultView(dvm: dvm, hovered: .constant(nil))
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted)),
                                  width: width, height: 500, appearance: appearance)
        defer { mount.drop() }

        let tree = ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                           children: [folder("/Volumes/Big/Sub", bytes: 600)]),
                              freeBytes: 100, filesScanned: 263_144, seconds: 12)
        // Stopped is a state only a walk in flight can reach: a partial snapshot
        // has to have arrived, and then Stop pressed. Anything else is the volume
        // picker, which draws no header at all. The scan task is not awaited —
        // Stop leaves the engine's own request parked for ever, which is what the
        // button does in life and what `StopKeepsWhatItMeasuredTests` already
        // relies on.
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.emitPartial(scan: transport.scanID(0), result: tree)
        await settle()
        if stopped {
            dvm.cancel()
        } else {
            transport.release(0, with: tree)
        }
        await settle()
        XCTAssertEqual(dvm.stopped, stopped, "precondition: the tree is in the state under test")
        XCTAssertNotNil(dvm.result, "precondition: there is a tree to say something about")
        mount.settle(20)
        return try XCTUnwrap(mount.settledInk(0...44), "the header never settled")
    }
}
