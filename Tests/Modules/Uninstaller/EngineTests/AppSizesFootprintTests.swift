import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// What measuring every installed bundle costs the process.
///
/// The open question from the 48 GB hunt (docs/superpowers/plans,
/// 2026-07-28 and 2026-07-29): the app grew **+177 MB** around the Uninstaller
/// page opening, and both hypotheses were falsified — the per-app icons cost
/// 3.9 MB at the row's real 28×28, and "bundle sizing costs single-digit MB".
///
/// Reading the trace again puts the growth inside `appSizes` rather than before
/// it. `HelmLog.memory` labels are written when an operation *ends*, so
///
///     23:11:49  idle: 56 MB
///     23:12:34  idle: 233 MB (+177 MB)   ← "before any command was logged"
///     23:12:40  uninstaller.appSizes: 260 MB
///
/// says the idle sample landed six seconds before `appSizes` finished — while it
/// was running. The command was not logged yet; it was not "not running".
///
/// So this measures the real path — `WorkspaceAppLister.appSizes`, over this
/// machine's real `/Applications` — rather than a synthetic tree, because the
/// shape that matters is one enormous bundle beside thirty small ones. Xcode is
/// hundreds of thousands of entries in a single `FileManager.enumerator` walk,
/// and eight such walks run at once under `DispatchQueue.concurrentPerform`,
/// which drains no autorelease pool per iteration.
///
///     HELM_BENCH=1 swift test --filter AppSizesFootprintTests
final class AppSizesFootprintTests: XCTestCase {

    private func lister() -> WorkspaceAppLister {
        WorkspaceAppLister(home: FileManager.default.homeDirectoryForCurrentUser,
                           fs: FMFileSystem())
    }

    func testMeasuringEveryInstalledBundleCostsBoundedMemory() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let lister = lister()
        let apps = lister.installedApps()
        try XCTSkipIf(apps.count < 5, "only \(apps.count) apps here; nothing to measure")

        let before = try XCTUnwrap(MemoryFootprint.current())
        let started = Date()
        let sizes = lister.appSizes(apps)
        let seconds = Date().timeIntervalSince(started)
        let after = try XCTUnwrap(MemoryFootprint.current())

        let grewMB = Double(after - before) / 1_048_576
        let totalGB = Double(sizes.values.reduce(0, +)) / 1_073_741_824
        print(String(format: "sized %d bundles (%.1f GB) in %.1fs: footprint grew %.1f MB",
                     apps.count, totalGB, seconds, grewMB))
        // The biggest bundles, because one of them could be the whole cost.
        let biggest = sizes.sorted(by: { $0.value > $1.value }).prefix(5)
        for (path, bytes) in biggest {
            print(String(format: "  %8.2f GB  %@",
                         Double(bytes) / 1_073_741_824, (path as NSString).lastPathComponent))
        }

        XCTAssertFalse(sizes.isEmpty, "nothing was measured")
        // Bundle sizing walks metadata, never contents: it should cost about what
        // a directory listing costs, not what the bundles weigh. The ceiling is
        // deliberately far above a healthy figure and far below the 177 MB this
        // test exists to explain — see ARCHITECTURE.md § Memory.
        XCTAssertLessThan(grewMB, 40,
                          "measuring \(apps.count) bundles grew the process by "
                          + String(format: "%.1f MB", grewMB)
                          + " — it walks metadata, so it should cost a listing, not a copy")
    }

    /// Everything else opening the page runs, so the page's own work can be
    /// accounted for entirely rather than one step at a time.
    ///
    /// `UninstallerSettingsPage.task` does exactly two things: reads the Full Disk
    /// Access state, and `loadAppsIfNeeded()` — which is `installedApps()` and then
    /// `appSizes()`. If all three together are single-digit MB, the +177 MB is not
    /// in the module's page at all, and the next suspect is the settings window
    /// itself, which needs a live build to separate.
    func testTheWholePageOpeningPathCostsBoundedMemory() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let lister = lister()

        // Repeated, because a first call warms caches Foundation and
        // LaunchServices keep for the life of the process, and a one-shot reading
        // cannot tell a warm-up from a leak. Growth that scales with the count is
        // the thing worth finding.
        var report: [String] = []
        for round in 1...3 {
            let before = try XCTUnwrap(MemoryFootprint.current())
            let access = PermissionCheck.currentFullDiskAccess()
            let afterAccess = try XCTUnwrap(MemoryFootprint.current())
            let apps = lister.installedApps()
            let afterList = try XCTUnwrap(MemoryFootprint.current())
            _ = lister.appSizes(apps)
            let afterSizes = try XCTUnwrap(MemoryFootprint.current())
            report.append(String(
                format: "round %d (access=%@, %d apps): fda %+.1f, list %+.1f, sizes %+.1f, "
                + "total %+.1f MB",
                round, String(describing: access), apps.count,
                Double(afterAccess - before) / 1_048_576,
                Double(afterList - afterAccess) / 1_048_576,
                Double(afterSizes - afterList) / 1_048_576,
                Double(afterSizes - before) / 1_048_576))
        }
        report.forEach { print($0) }

        let start = try XCTUnwrap(MemoryFootprint.current())
        for _ in 1...3 { _ = lister.appSizes(lister.installedApps()) }
        let end = try XCTUnwrap(MemoryFootprint.current())
        let perRound = Double(end - start) / 1_048_576 / 3
        print(String(format: "three further rounds: %+.1f MB per round", perRound))

        XCTAssertLessThan(perRound, 10, """
            Opening the page costs \(String(format: "%.1f", perRound)) MB every time it \
            is opened, which is the shape the +177 MB report describes. \
            docs/superpowers/plans/2026-07-28-review-leftovers.md has the trace.
            """)
    }
}
