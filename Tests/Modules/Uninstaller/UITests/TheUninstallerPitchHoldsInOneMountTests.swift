import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The Uninstaller page carried through every step in ONE mount, the way a
/// person does it in one window** — pick, review, back, review, a partly
/// refused removal, the failure report, dismiss, pick — and then the same
/// mount through every language. The failure report mounted fresh is
/// `testATallFailureRowDoesNotRaiseTheShortOne`'s; the rest of this file is the
/// route a fresh mount steps around: the page swaps a whole branch
/// (`if !failures.isEmpty`) inside one hosting view, and the table under it
/// has to be at the declared pitch after every swap. (The comment of a test
/// since removed recorded that this page once reused one `NSTableView` across
/// all three steps and the empty area's `rowHeight` did not follow to the
/// third — carried over here as that comment's word, not re-measured.)
///
/// Each step reads the table's `rowHeight`, the rows, and the pitch the empty
/// area is actually painted at (`StripedEmptyAreaPitch`).
@MainActor
final class TheUninstallerPitchHoldsInOneMountTests: XCTestCase {

    private static let pitch = HelmSpace.s8

    private static let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                           path: "/Applications/Tool.app", sizeBytes: 4_096)

    private static var leftovers: [Leftover] {
        [Leftover(path: "\(NSHomeDirectory())/Library/Caches/com.acme.tool",
                  kind: .caches, sizeBytes: 2_048, matchedByName: false),
         Leftover(path: "\(NSHomeDirectory())/Library/Preferences/com.acme.tool.plist",
                  kind: .preferences, sizeBytes: 1_024, matchedByName: false)]
    }

    private static let longMessage = "The operation couldn’t be completed because the item is in use "
        + "by another process that holds it open and macOS refused to move it to the Trash."

    private static var twoRefusals: [TrashFailureInfo] {
        [TrashFailureInfo(path: tool.path, reason: .needsFullDiskAccess, message: "denied"),
         TrashFailureInfo(path: leftovers[1].path, reason: .noPermission, message: "denied")]
    }

    private func wire(_ failures: [TrashFailureInfo]) -> UninstallerWire {
        UninstallerWire(
            apps: [Self.tool],
            scans: [Self.tool.bundleID: ScanResult(bundleID: Self.tool.bundleID,
                                                   appPath: Self.tool.path, appSizeBytes: 0,
                                                   leftovers: Self.leftovers, runningNow: false)],
            removal: UninstallResult(trashed: [Self.leftovers[0].path], freedBytes: 2_048,
                                     failures: failures))
    }

    /// What `SettingsWindow` does on a language change: bump a revision the
    /// content is identified by.
    final class Revision: ObservableObject { @Published var value = 0 }

    struct Page: View {
        let vm: ModuleViewModel
        @ObservedObject var revision: Revision
        var body: some View {
            UninstallerSettingsPage(vm: vm)
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted))
                .id(revision.value)
        }
    }

    private func mountPage(_ vm: ModuleViewModel, _ revision: Revision = Revision(),
                           onScreen: Bool = false) -> MountedRender {
        let mount = MountedRender(Page(vm: vm, revision: revision),
                                  width: 700, height: 540, appearance: .aqua)
        if onScreen { mount.window?.orderFrontRegardless() }
        return mount
    }

    private enum Rows { case atThePitch, atLeastThePitch }

    /// One step's reading, asserted. Returns the rows it read, headers left out.
    @discardableResult
    private func assertStep(_ mount: MountedRender, _ label: String, rows kind: Rows,
                            file: StaticString = #filePath, line: UInt = #line) -> [CGFloat] {
        let tables = mount.host.everyView(ofType: NSTableView.self)
        XCTAssertEqual(tables.count, 1, "\(label): \(tables.count) tables under the page", file: file, line: line)
        guard let table = tables.first else { return [] }
        let rows = StripedListPitch.realRowHeights(in: table)
        let painted = StripedEmptyAreaPitch.read(mount.host, table)
        print("PITCH[\(label)] rowHeight=\(table.rowHeight) rows=\(rows) "
              + "painted \(painted.map { "\($0)" } ?? "unreadable")")
        XCTAssertTrue(table.usesAlternatingRowBackgroundColors, "\(label): not striped", file: file, line: line)
        XCTAssertEqual(table.rowHeight, Self.pitch, accuracy: 0.5, """
            \(label): rowHeight is \(table.rowHeight) where the page declared \(Self.pitch)
            """, file: file, line: line)
        XCTAssertEqual(painted?.pitch ?? -1, Self.pitch, accuracy: 1, """
            \(label): the empty area is painted at \(painted?.pitch.map { "\($0)" } ?? "no readable pitch") \
            where the page declared \(Self.pitch)
            """, file: file, line: line)
        XCTAssertFalse(rows.isEmpty, "\(label): no non-header row", file: file, line: line)
        for height in rows {
            switch kind {
            case .atThePitch:
                XCTAssertEqual(height, Self.pitch, accuracy: 0.5,
                               "\(label): a row is \(height) pt where a one-line row reads \(Self.pitch)",
                               file: file, line: line)
            case .atLeastThePitch:
                XCTAssertGreaterThanOrEqual(height, Self.pitch - 0.5,
                                            "\(label): a row is \(height) pt, under the \(Self.pitch) pt pitch",
                                            file: file, line: line)
            }
        }
        return rows
    }

    private func throughEveryStep(onScreen: Bool) async throws {
        let vm = ModuleViewModel(transport: wire(Self.twoRefusals))
        let uvm = UninstallerViewModel.shared(vm: vm)
        let mount = mountPage(vm, onScreen: onScreen)
        defer { mount.drop() }
        let tag = onScreen ? "on screen" : "off screen"

        await uvm.loadAppsIfNeeded()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .pick, "precondition: the picker is up first")
        assertStep(mount, "\(tag) pick", rows: .atThePitch)

        uvm.setChecked(Self.tool.bundleID, true)
        await uvm.prepareReview()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .review, "precondition: review followed the pick")
        assertStep(mount, "\(tag) review", rows: .atThePitch)

        uvm.backToPick()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .pick, "precondition: back to the pick")
        assertStep(mount, "\(tag) back to pick", rows: .atThePitch)

        await uvm.prepareReview()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .review, "precondition: review again")
        assertStep(mount, "\(tag) review again", rows: .atThePitch)

        await uvm.removeSelection()
        XCTAssertFalse(uvm.failures.isEmpty, "precondition: the removal was partly refused")
        mount.settle(30)
        assertStep(mount, "\(tag) failure report", rows: .atLeastThePitch)
        mount.settle(60)
        assertStep(mount, "\(tag) failure report +60", rows: .atLeastThePitch)

        uvm.dismissFailures()
        mount.settle(30)
        XCTAssertTrue(uvm.failures.isEmpty, "precondition: the report was dismissed")
        assertStep(mount, "\(tag) after dismiss", rows: .atThePitch)
    }

    func testOffScreenOneMountThroughEveryStep() async throws {
        try await throughEveryStep(onScreen: false)
    }

    func testOnScreenOneMountThroughEveryStep() async throws {
        try await throughEveryStep(onScreen: true)
    }

    /// **A row's height does not depend on which screen came before it.** The
    /// review mounted fresh is the reference for the review reached from the
    /// pick in the same mount.
    func testTheReviewDrawsTheSameRowsWhicheverWayItWasReached() async throws {
        let freshVM = ModuleViewModel(transport: wire(Self.twoRefusals))
        let freshUVM = UninstallerViewModel.shared(vm: freshVM)
        await freshUVM.loadAppsIfNeeded()
        freshUVM.setChecked(Self.tool.bundleID, true)
        await freshUVM.prepareReview()
        let fresh = mountPage(freshVM)
        defer { fresh.drop() }
        fresh.settle(30)
        let freshTable = try XCTUnwrap(fresh.host.everyView(ofType: NSTableView.self).first)
        let freshRows = (0..<freshTable.numberOfRows).map { freshTable.rect(ofRow: $0).height }

        let vm = ModuleViewModel(transport: wire(Self.twoRefusals))
        let uvm = UninstallerViewModel.shared(vm: vm)
        let mount = mountPage(vm)
        defer { mount.drop() }
        await uvm.loadAppsIfNeeded()
        mount.settle(30)
        uvm.setChecked(Self.tool.bundleID, true)
        await uvm.prepareReview()
        mount.settle(30)
        let table = try XCTUnwrap(mount.host.everyView(ofType: NSTableView.self).first)
        let rows = (0..<table.numberOfRows).map { table.rect(ofRow: $0).height }
        print("PITCH[review fresh] rows=\(freshRows) | PITCH[review after pick] rows=\(rows)")
        XCTAssertFalse(rows.isEmpty, "precondition: the review drew rows")
        XCTAssertEqual(rows, freshRows, "the review's rows depend on the screen before it")
    }

    /// **A tall failure row does not raise a short one.** Same reason on both
    /// rows, the message is the only difference; each order is mounted fresh,
    /// and the short row must be the same height under the tall one as above it.
    func testATallFailureRowDoesNotRaiseTheShortOne() async throws {
        var byOrder: [String: [CGFloat]] = [:]
        for (tag, failures) in [
            ("tallFirst", [TrashFailureInfo(path: Self.tool.path, reason: .noPermission,
                                            message: Self.longMessage),
                           TrashFailureInfo(path: Self.leftovers[1].path, reason: .noPermission, message: "")]),
            ("shortFirst", [TrashFailureInfo(path: Self.leftovers[1].path, reason: .noPermission, message: ""),
                            TrashFailureInfo(path: Self.tool.path, reason: .noPermission,
                                             message: Self.longMessage)])
        ] {
            let vm = ModuleViewModel(transport: wire(failures))
            let uvm = UninstallerViewModel.shared(vm: vm)
            await uvm.loadAppsIfNeeded()
            uvm.setChecked(Self.tool.bundleID, true)
            await uvm.prepareReview()
            await uvm.removeSelection()
            XCTAssertFalse(uvm.failures.isEmpty, "precondition: partly refused")
            let mount = mountPage(vm)
            mount.settle(30)
            byOrder[tag] = assertStep(mount, "failure \(tag)", rows: .atLeastThePitch)
            mount.drop()
        }
        let tall = try XCTUnwrap(byOrder["tallFirst"]), short = try XCTUnwrap(byOrder["shortFirst"])
        XCTAssertEqual(tall.count, 2, "precondition: two failure rows")
        XCTAssertEqual(short.count, 2, "precondition: two failure rows")
        guard tall.count == 2, short.count == 2 else { return }
        XCTAssertNotEqual(tall[0], tall[1], "precondition: the two rows differ in height")
        XCTAssertEqual(tall[0], short[1], "the long-message row changed height with its position")
        XCTAssertEqual(tall[1], short[0], """
            the empty-message row is \(tall[1]) pt under a tall row and \(short[0]) pt above it
            """)
    }

    /// **A language change in the same mount keeps the pitch** — review and
    /// the failure report remounted under every language the way
    /// `SettingsWindow` remounts its content (`content.id(model.languageRevision)`).
    /// A translation may wrap a row taller than the pitch; it may never draw
    /// one shorter, and the table under it stays at the declared number.
    func testALanguageChangeInOneMountKeepsThePitch() async throws {
        let vm = ModuleViewModel(transport: wire(Self.twoRefusals))
        let uvm = UninstallerViewModel.shared(vm: vm)
        let revision = Revision()
        let mount = mountPage(vm, revision)
        defer { mount.drop() }
        await uvm.loadAppsIfNeeded()
        mount.settle(30)
        uvm.setChecked(Self.tool.bundleID, true)
        await uvm.prepareReview()
        mount.settle(30)
        XCTAssertEqual(uvm.step, .review, "precondition: review")

        var previous = mount.host.everyView(ofType: NSTableView.self).first
        AppLanguage.each { language in
            revision.value += 1
            mount.settle(30)
            let table = mount.host.everyView(ofType: NSTableView.self).first
            XCTAssertFalse(table === previous, "precondition: the change to \(language) built a new table")
            previous = table
            assertStep(mount, "review in \(language)", rows: .atLeastThePitch)
        }

        await uvm.removeSelection()
        XCTAssertFalse(uvm.failures.isEmpty, "precondition: the removal was partly refused")
        mount.settle(30)
        AppLanguage.each { language in
            revision.value += 1
            mount.settle(30)
            assertStep(mount, "failure report in \(language)", rows: .atLeastThePitch)
        }
    }
}
