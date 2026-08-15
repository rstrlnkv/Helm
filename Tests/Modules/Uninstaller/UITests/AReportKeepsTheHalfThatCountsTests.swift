import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The report of a partly-failed removal lost a third of itself at the app's own
/// minimum width.**
///
/// `UnStr.movedWithFailures` — «Moved to the Trash — 4 KB, 2 items could not be
/// moved» — was a `lineLimit(1)` passenger in the pick footer, an `HStack` that also
/// holds two buttons and a status line. Measured in pixel columns of ink, 845 pt
/// against 646 pt: English unchanged, **de −30 %**, **ru −39 %**, and the row did
/// **not** grow — so this was truncation, and what a truncated `movedWithFailures`
/// loses is its tail, which is the half that says how many items stayed behind.
/// 646 pt is the detail pane at `contentMinSize`, so it is a real width.
///
/// The fix is the one Leftovers landed for the same shape: the report is a
/// full-width line of its own above the bar, where it can wrap.
///
/// **What is measured is the growth, not the sentence.** A report that has a line
/// of its own takes height from the list; a report squeezed into the button row
/// takes none, whatever it has had to drop to fit. So the reading is what the
/// report costs the list — `ListCoreScrollView` is what SwiftUI backs a `List`
/// with, and its frame is the room the rows have — and the claim is that the cost
/// is at least a line, and no smaller at the narrow width than at the wide one,
/// where the sentence needs two lines rather than one.
///
/// Parameterized by an explicit language: this defect is a translation running out
/// of room, and `AppLanguage.current` on this machine would exercise one of them.
@MainActor
final class AReportKeepsTheHalfThatCountsTests: XCTestCase {

    private static let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                           path: "/Applications/Tool.app", sizeBytes: 4_096)

    private static var leftovers: [Leftover] {
        [Leftover(path: "\(NSHomeDirectory())/Library/Caches/com.acme.tool",
                  kind: .caches, sizeBytes: 2_048, matchedByName: false),
         Leftover(path: "\(NSHomeDirectory())/Library/Preferences/com.acme.tool.plist",
                  kind: .preferences, sizeBytes: 1_024, matchedByName: false)]
    }

    /// One moved, two refused: the only shape that draws `movedWithFailures`, which
    /// is the sentence with a tail to lose.
    private static var partlyRefused: UninstallResult {
        UninstallResult(
            trashed: [leftovers[0].path], freedBytes: 2_048,
            failures: [TrashFailureInfo(path: tool.path, reason: .needsFullDiskAccess,
                                        message: "denied"),
                       TrashFailureInfo(path: leftovers[1].path, reason: .noPermission,
                                        message: "denied")])
    }

    private func wire() -> UninstallerWire {
        UninstallerWire(
            apps: [Self.tool],
            scans: [Self.tool.bundleID: ScanResult(bundleID: Self.tool.bundleID,
                                                   appPath: Self.tool.path, appSizeBytes: 0,
                                                   leftovers: Self.leftovers, runningNow: false)],
            removal: Self.partlyRefused)
    }

    /// The list's height on the picker before the press and after it, from one
    /// mount: the same page, the same rows, one report between the two readings.
    ///
    /// One mount rather than two, and it is not only cheaper — two mounts differ by
    /// however AppKit felt about the second window, and the quantity here is a
    /// difference of about twenty points.
    private func listHeightAroundTheReport(language: AppLanguage, width: CGFloat,
                                           appearance: NSAppearance.Name) async throws
        -> (before: CGFloat, after: CGFloat) {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = language

        let wire = wire()
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        let mount = MountedRender(UninstallerSettingsPage(vm: vm)
            // Named, never inherited: the page draws a permission note off this
            // answer, and without a reading the measurement would be a fact about
            // the grants of whichever process ran the suite.
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted)),
                                  width: width, height: 540, appearance: appearance)
        defer { mount.drop() }

        await uvm.loadAppsIfNeeded()
        uvm.setChecked(Self.tool.bundleID, true)
        await uvm.prepareReview()
        uvm.backToPick()
        mount.settle(30)
        let before = try XCTUnwrap(Self.list(in: mount.host)?.height,
                                   "no list on the picker at all, so nothing below is measured")

        uvm.setChecked(Self.tool.bundleID, true)
        await uvm.prepareReview()
        await uvm.removeSelection()
        XCTAssertFalse(uvm.failures.isEmpty, "precondition: the removal was partly refused")
        // The sheet is a screen of its own; the line this file is about is the one
        // left standing on the picker after «Done».
        uvm.dismissFailures()
        XCTAssertEqual(uvm.step, .pick, "precondition: the picker is back")
        XCTAssertNotNil(uvm.resultBanner, "precondition: the report is on the page")
        mount.settle(30)
        let after = try XCTUnwrap(Self.list(in: mount.host)?.height,
                                  "the list left the page with the report")
        return (before, after)
    }

    private static func list(in host: NSView) -> CGRect? {
        // The list is the tallest of them: SwiftUI nests scroll views, and the
        // outer one is the page.
        host.everyView.filter { $0.appKitClassName.contains("ListCoreScrollView") }
            .map { $0.convert($0.bounds, to: host) }
            .max { $0.height < $1.height }
    }

    // MARK: -

    /// **The measurement.** At the app's own minimum width the report has a line of
    /// its own, and that line costs the list height — which is what a report that
    /// truncates instead never does.
    func testTheReportTakesALineOfItsOwnAtTheMinimumWidth() async throws {
        for appearance in RenderedInk.bothAppearances {
            let (before, after) = try await listHeightAroundTheReport(language: .ru, width: 646,
                                                                     appearance: appearance)

            XCTAssertGreaterThan(before, 0,
                                 "\(RenderedInk.label(of: appearance)): no list to lose height")
            XCTAssertGreaterThanOrEqual(before - after, 16, """
                \(RenderedInk.label(of: appearance)): the report cost the list \
                \(Int(before - after)) pt at 646 pt wide, which is not a line — a sentence that \
                takes no room is a sentence that fitted itself by dropping its tail, and the \
                tail of `movedWithFailures` is how many items could not be moved
                """)
            XCTAssertLessThanOrEqual(before - after, 100, """
                \(RenderedInk.label(of: appearance)): the report cost the list \
                \(Int(before - after)) pt, which is Leftovers' defect read the other way — a \
                report is a line, not a panel
                """)
        }
    }

    /// And it grows into the narrow width rather than fitting itself into it: the
    /// Russian sentence needs two lines at 646 pt and one at 845, so what it costs
    /// the list cannot be smaller at the width where it has less room.
    func testTheReportCostsNoLessRoomWhereItHasLessWidth() async throws {
        for appearance in RenderedInk.bothAppearances {
            let wide = try await listHeightAroundTheReport(language: .ru, width: 845,
                                                          appearance: appearance)
            let narrow = try await listHeightAroundTheReport(language: .ru, width: 646,
                                                            appearance: appearance)
            let wideCost = wide.before - wide.after
            let narrowCost = narrow.before - narrow.after

            XCTAssertGreaterThan(wideCost, 0, """
                \(RenderedInk.label(of: appearance)): the report took no room at 845 pt either, \
                so the comparison below is between two nothings
                """)
            XCTAssertGreaterThanOrEqual(narrowCost, wideCost, """
                \(RenderedInk.label(of: appearance)): the report costs \(Int(narrowCost)) pt at \
                646 and \(Int(wideCost)) pt at 845 — it is fitting itself into the narrow width \
                instead of growing into it, which is what truncation looks like from here
                """)
        }
    }

    /// English is the control, and the language the defect never touched: it fitted
    /// at both widths, so it must not be the reason the numbers above pass.
    func testTheEnglishReportTakesALineOfItsOwnToo() async throws {
        let (before, after) = try await listHeightAroundTheReport(language: .en, width: 646,
                                                                 appearance: .aqua)

        XCTAssertGreaterThan(before, 0, "no list to lose height")
        XCTAssertGreaterThanOrEqual(before - after, 16, """
            the English report cost the list \(Int(before - after)) pt, so it is still a \
            passenger in the button row and the reflow only happened for the long translations
            """)
    }
}
