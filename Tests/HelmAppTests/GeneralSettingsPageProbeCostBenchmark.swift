import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **`GeneralSettingsPage` is the sixth page with this shape, and the fifth of
/// six is where the fix stopped.**
///
/// `HelmFullDiskTracker`/`HelmAccessibilityTracker` (`PermissionNote.swift`)
/// exist because "five settings pages carried the same `@State`, the same
/// `.helmOnAppActive` and the same line inside their own `.task`" — reading
/// `PermissionCheck.currentFullDiskAccess()` and `.currentAccessibility()`
/// synchronously, on the thread that draws, every time the app returns to the
/// front. Uninstaller, Disk, Leftovers, Autopilot and Duplicates now go through
/// `.helmTracksFullDiskAccess`, which hops the disk probe off the cooperative
/// pool with `await PermissionCheck.fullDiskAccess()` (`PermissionNote.swift`'s
/// own doc: "the probe stays asynchronous… four blocking file reads belong off
/// the cooperative pool").
///
/// `GeneralSettingsPage.swift` never moved. Its `.task` and its
/// `.onReceive(didBecomeActiveNotification)` both still call
/// `PermissionCheck.currentFullDiskAccess()` and `.currentAccessibility()`
/// directly — the synchronous forms — so every time Settings' General page is
/// open and the app comes back to the front (clicking back in from another
/// app, dismissing a system dialog, returning from System Settings after
/// granting something), this page's four blocking file reads run on
/// `com.apple.main-thread`, unlike every other page that asks the same
/// question.
///
/// This file does not assert — a source-scanning guard here would go red on a
/// defect nobody has agreed is worth the same fix (`.helmTracksFullDiskAccess`
/// forces a one-frame-later reveal that traded against, per its own comment,
/// "the answer lands a hop later than it used to"), so this is a report next to
/// a citation, in the shape `ScanBenchmark` uses for a timing figure: printed,
/// gated, and left for the reader to act on.
///
/// `HELM_BENCH=1 swift test --filter GeneralSettingsPageProbeCostBenchmark`
final class GeneralSettingsPageProbeCostBenchmark: XCTestCase {

    /// The two call sites, cited so this file goes stale (rather than silently
    /// wrong) the day somebody edits the page without reading this comment.
    func testGeneralSettingsPageStillCallsTheSynchronousProbes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let path = "Sources/HelmApp/GeneralSettingsPage.swift"
        let lines = try RepoSource.lines(of: path)
        var hits: [String] = []
        for (index, line) in lines.enumerated() {
            let code = RepoSource.code(line)
            if code.contains("PermissionCheck.currentFullDiskAccess()")
                || code.contains("PermissionCheck.currentAccessibility()") {
                hits.append("\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        print("GeneralSettingsPage.swift calls the synchronous probes at:")
        hits.forEach { print("  \($0)") }
        // Not an assertion: recording where the calls are, not whether they
        // should be there. `HelmFullDiskTracker` is the fix on offer if they
        // should not be.
        XCTAssertFalse(hits.isEmpty, """
            this file's whole claim is that these lines exist — if they are gone, \
            GeneralSettingsPage has already been moved onto \
            `.helmTracksFullDiskAccess`/`.helmTracksAccessibility` and this benchmark (and its \
            comment) are the stale part now
            """)
    }

    /// What each of those calls costs, measured directly rather than trusted
    /// from `PermissionCheck.swift`'s own doc comment (0.09 ms warm, 1.85 ms
    /// cold, measured on a different Mac under different grants). Ten cold-ish
    /// calls (a fresh probe list each time defeats nothing — the OS file cache
    /// is what actually warms) followed by ninety warm ones.
    func testWhatOneCallCosts() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        var samples: [Double] = []
        for _ in 0..<100 {
            let start = Date()
            _ = PermissionCheck.currentFullDiskAccess()
            samples.append(Date().timeIntervalSince(start) * 1000)
        }
        let first = samples.first ?? 0
        let rest = samples.dropFirst()
        let warmAverage = rest.reduce(0, +) / Double(rest.count)
        let warmMax = rest.max() ?? 0
        print(String(format: "currentFullDiskAccess(): first call %.3f ms, "
                     + "average of next 99 %.3f ms, worst of those %.3f ms",
                     first, warmAverage, warmMax))
        // No ceiling asserted on purpose — `PermissionCheck.swift`'s own doc
        // comment on `fullDiskAccess(probing:)` is the argument against one:
        // "those milliseconds have no ceiling: each is a synchronous open and a
        // read of somebody's chat.db or Safari bookmarks… a blocking syscall
        // answers when it answers." A threshold here would assert the thing
        // this file exists to say cannot be assumed.
    }

    /// **The same page's `launchAtLogin` is the other half of this family, and it
    /// is not behind `HelmFullDiskTracker` at all — there is no tracker for it.**
    /// `@State private var launchAtLogin: LoginItemState = LoginItem.current()`
    /// runs `SMAppService.mainApp.status` inside the `@State` initial value,
    /// which SwiftUI evaluates when it installs the page's state — inside
    /// `SettingsWindow.init`, the same place `disabledScans` used to be read
    /// before it was made lazy (`AppSettings.swift`'s own doc on that fix). The
    /// same call runs again, synchronously, in `.onReceive(didBecomeActive)` at
    /// line 433 — every time this window regains focus.
    ///
    /// **Caveat, stated rather than hidden**: this test asks `SMAppService` from
    /// an `xctest` process, not from `Helm.app`'s own bundle — there is no
    /// `LaunchServices` registration or `Info.plist` behind this binary, which
    /// is not the condition the real call runs under. The number below is what
    /// this harness can measure, not a claim about the installed app; an
    /// in-app reading (an `os_signpost` around the `@State` line, the way
    /// `HelmActivity.phase` already wraps heavy work elsewhere) is what would
    /// turn this from an inference into a measurement.
    func testWhatSMAppServiceStatusCostsFromThisHarness() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = Date()
            _ = LoginItem.current()
            samples.append(Date().timeIntervalSince(start) * 1000)
        }
        print("LoginItem.current() from xctest: \(samples.map { String(format: "%.1f", $0) })" +
              " ms — not the installed app's own cost, see this test's doc comment")
    }
}
