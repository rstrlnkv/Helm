import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// One bundle id, two copies on disk, two rows: the picker's `InstalledApp`
/// and the Trash window's `TrashedAppLeftovers` identify by path, as
/// `UninstallGroup.id` does (`AppSizeIdentityTests` for the sizes and the
/// plan). A `ForEach` given one identity for two rows has undefined results,
/// over checkboxes on somebody's files.
@MainActor
final class TwoCopiesOfOneAppAreTwoRowsTests: XCTestCase {

    // MARK: -

    /// The unprompted window, end to end: the engine hands back two groups for
    /// two copies of one app in the Trash.
    func testTheTrashOfferGivesEachTrashedCopyItsOwnIdentity() async {
        let home = URL(fileURLWithPath: "/Users/ann")
        let store = NamespacedStore(namespace: "uninstaller", backing: InMemoryKeyValueStore())
        store.set(true, for: "watchTrash")
        // Delete, reinstall, delete again: the Finder keeps both and renames the
        // second. One `Info.plist`, so one bundle id.
        let lister = FakeApps(trashed: [
            TrashedApp(bundleID: "com.acme.tool", name: "Tool", path: "/Users/ann/.Trash/Tool.app"),
            TrashedApp(bundleID: "com.acme.tool", name: "Tool", path: "/Users/ann/.Trash/Tool 2.app"),
        ])
        let engine = UninstallerEngine(home: home, apps: lister, fs: FakeFS(everyPathExistsAt: 4_096),
                                       trash: NoTrash(), running: NoRunning(), store: store)

        let groups = await engine.trashedAppLeftovers()

        XCTAssertEqual(groups.count, 2,
                       "precondition: the sweep offers both copies, so the window draws both")
        XCTAssertEqual(Set(groups.map(\.id)).count, 2, """
            the two cards carry one identity into the window's ForEach. A group that is in \
            `model.groups` but not on screen still contributes its paths to what Move to \
            Trash sends — «what one press sends has to be exactly what was listed above it» \
            is `TrashOfferPlan`'s own promise, and identity is what keeps it.
            """)
    }

    /// The tick: two installed copies share an id, and ticking one reviews
    /// exactly that copy and sends only its bundle path to the Trash.
    func testTickingOneOfTwoCopiesReviewsAndRemovesOnlyThatCopy() async throws {
        let direct = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                  path: "/Applications/Tool.app")
        let setapp = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                  path: "/Users/ann/Applications/Setapp/Tool.app")
        let work = AnsweringWork(apps: [direct, setapp],
                                 scans: ["com.acme.tool": ScanResult(leftovers: [], runningNow: false)],
                                 removal: UninstallResult(trashed: [setapp.path], freedBytes: 1))
        let uvm = modelOver(work)
        await uvm.loadAppsIfNeeded()

        uvm.setChecked(setapp, true)
        XCTAssertTrue(uvm.isChecked(setapp), "the ticked copy is not ticked")
        XCTAssertFalse(uvm.isChecked(direct), "ticking one copy ticked the other, which shares its id")
        await uvm.prepareReview()
        XCTAssertEqual(uvm.groups.map(\.app.path), [setapp.path])

        await uvm.removeSelection()
        let batch = try XCTUnwrap(work.batches.last, "the removal was never sent")
        XCTAssertEqual(batch.paths, [setapp.path])
    }

    /// The control: two different apps are two rows, so the assertions above and
    /// in `TheAppPickerGivesEachCopyItsOwnIdentityTests` cannot pass vacuously.
    func testTwoDifferentAppsAreStillTwoRows() {
        let one = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                               path: "/Applications/Tool.app")
        let other = InstalledApp(name: "Other", bundleID: "com.acme.other",
                                 path: "/Applications/Other.app")
        XCTAssertEqual(Set([one, other].map(\.id)).count, 2)

        let first = TrashedAppLeftovers(bundleID: "com.acme.tool", name: "Tool",
                                        appPath: "/Users/ann/.Trash/Tool.app", leftovers: [])
        let second = TrashedAppLeftovers(bundleID: "com.acme.other", name: "Other",
                                         appPath: "/Users/ann/.Trash/Other.app", leftovers: [])
        XCTAssertEqual(Set([first, second].map(\.id)).count, 2)
    }
}

/// The picker's half of the same rule: two installed copies of one app share a
/// bundle id, and the picker still has to tell them apart.
@MainActor
final class TheAppPickerGivesEachCopyItsOwnIdentityTests: XCTestCase {

    /// The picker. Two installed copies, one row.
    func testTheAppPickerGivesEachInstalledCopyItsOwnIdentity() {
        let direct = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                  path: "/Applications/Tool.app")
        let setapp = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                  path: "/Users/ann/Applications/Setapp/Tool.app")

        XCTAssertEqual(Set([direct, setapp].map(\.id)).count, 2, """
            two installed copies of one app carry one identity into the picker's ForEach, \
            which SwiftUI answers with «undefined results». The review screen behind it \
            already identifies them by path (`UninstallGroup.id`) and removes both, so the \
            list that queues them is the one place that cannot tell them apart.
            """)
    }
}
