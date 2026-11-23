import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Pass 19 let one watcher (the oldest) read for all. These try what that leaves: a change that arrives while the oldest is mid-read and
/// then leaves, a window opened over a page that already holds the snapshot, the open phase ending on a first snapshot, and a launch's new
/// count reaching the page and the window, a gone app's launch refreshing the page away included.
@MainActor
final class TheWatchersOfTheLaunchpadNeverLoseAChangeTests: XCTestCase {
    /// A catalog whose watch read can be held: the first `.watch` read takes its reading, then waits for `release()`.
    private final class HeldCatalog: AppCatalogPort, @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String]
        private var holdFirstWatch = true
        private var enteredFlag = false
        var didEnter: Bool { lock.withLock { enteredFlag } }
        private let gate = DispatchSemaphore(value: 0)
        private var handlers: [Int: @Sendable () -> Void] = [:]
        private var next = 0
        init(_ ids: [String]) { self.ids = ids }
        func set(_ ids: [String]) { lock.withLock { self.ids = ids } }
        func release() { gate.signal() }
        func fire() { for h in lock.withLock({ Array(handlers.values) }) { h() } }
        func read(reason: CatalogReadReason) -> CatalogReading {
            let taken = lock.withLock { ids }
            if reason == .watch, lock.withLock({ defer { holdFirstWatch = false }; return holdFirstWatch }) {
                lock.withLock { enteredFlag = true }; gate.wait()
            }
            return CatalogReading(apps: taken.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }, complete: true)
        }
        func bundleID(atPath path: String) -> String? { nil }
        private final class Token { let r: () -> Void; init(_ r: @escaping () -> Void) { self.r = r }; deinit { r() } }
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
            let key = lock.withLock { next += 1; handlers[next] = onChange; return next }
            return Token { [weak self] in self?.lock.withLock { _ = self?.handlers.removeValue(forKey: key) } }
        }
    }

    /// The window's watch is reading change A when change B arrives and the window is closed: the page is the only watcher left, and the model
    /// must end up showing B's catalog.
    func testAChangeThatCameWhileTheOldestWasReadingAndThenLeftIsNotLost() async {
        let catalog = HeldCatalog(["a"])
        let engine = LaunchpadEngine(catalog: catalog, launcher: RigLauncher(), store: LayoutStore(directory: scratchDirectory("held")))
        let model = LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore()))
        let window = Task { await model.whileShown() }
        await waitUntil("the window's snapshot") { model.snapshot != nil }
        let page = Task { await model.whileShown(reason: .settings) }
        try? await Task.sleep(for: .milliseconds(200))
        catalog.fire()                                   // change A: the window's watch (the oldest) starts reading and is held
        await waitUntil("the held read began") { catalog.didEnter }
        catalog.set(["a", "b"])                          // change B: an app installed meanwhile
        catalog.fire()
        try? await Task.sleep(for: .milliseconds(200))   // the page's watch saw B and judged "the oldest reads"
        window.cancel()                                  // the window closes before it reads again
        try? await Task.sleep(for: .milliseconds(100))
        catalog.release()
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(model.snapshot?.apps.keys.sorted(), ["a", "b"], "the page is left watching and shows a catalog older than the change it was told of")
        page.cancel()
    }

    /// A page is open and holds the snapshot; the window opens over it. The open phase must end when the window has drawn, not stay "running"
    /// until it closes.
    func testTheOpenPhaseEndsWhenTheWindowOpensOverAPageThatAlreadyHoldsTheSnapshot() async {
        _ = NSApplication.shared
        let rig = LaunchpadRig(self, label: "open-over-page")
        let page = Task { await rig.model.whileShown(reason: .settings) }
        await waitUntil("the page's snapshot") { rig.model.snapshot != nil }
        tailTheLog()
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: panel.state!.geometry.size.width, height: panel.state!.geometry.size.height), display: false)
        window.present()
        for _ in 0..<40 where panel.state?.pages.first?.isEmpty != false { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(panel.state?.pages.first?.isEmpty, false, "the control: the window drew the tiles")
        try? await Task.sleep(for: .milliseconds(500))
        let open = HelmActivity.running.filter { $0.label == "launchpad.open" }
        XCTAssertTrue(open.isEmpty, "the open phase is still running with the window drawn")
        XCTAssertEqual(loggedLines("launchpad").filter { $0.hasPrefix("window: first snapshot landed") }.count, 1, "the open was not told its snapshot had landed")
        XCTAssertEqual(loggedLines("memory").filter { $0.hasPrefix("module.launchpad.show") }.count, 1, "no show line with the window drawn over a page that held the snapshot")
        window.close()
        try? await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(HelmActivity.running.filter { $0.label == "launchpad.open" }.isEmpty, "the control: it ends when the window closes")
        page.cancel()
    }

    /// The control of the phase: a window with no page beside it ends the phase when its first snapshot is drawn.
    func testTheOpenPhaseEndsWhenAloneWindowDrawsItsFirstSnapshot() async {
        _ = NSApplication.shared
        let rig = LaunchpadRig(self, label: "open-alone")
        tailTheLog()
        let before = Set(NSApp.windows.compactMap { $0 as? LaunchpadPanel }.map(ObjectIdentifier.init))
        let window = LaunchpadWindow(model: rig.model)
        let panel = NSApp.windows.compactMap { $0 as? LaunchpadPanel }.first { !before.contains(ObjectIdentifier($0)) }!
        panel.setFrame(CGRect(x: -20000, y: -20000, width: panel.state!.geometry.size.width, height: panel.state!.geometry.size.height), display: false)
        window.present()
        for _ in 0..<40 where panel.state?.pages.first?.isEmpty != false { try? await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(panel.state?.pages.first?.isEmpty, false)
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(loggedLines("memory").filter { $0.hasPrefix("module.launchpad.show") }.count, 1, "the control: the alone window logs its show line")
        XCTAssertTrue(HelmActivity.running.filter { $0.label == "launchpad.open" }.isEmpty, "the open phase is still running with the window drawn")
        window.close()
        try? await Task.sleep(for: .milliseconds(600))
    }

    private func make(_ label: String, apps: [String] = ["a", "b"]) -> (RigCatalog, LaunchpadViewModel) {
        let catalog = RigCatalog(apps)
        let engine = LaunchpadEngine(catalog: catalog, launcher: RigLauncher(answer: true), store: LayoutStore(directory: scratchDirectory(label)))
        return (catalog, LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())))
    }

    /// A launch from the settings page's context (no window): the page is the one watcher and must read the new count.
    func testALaunchWithOnlyThePageWatchingShowsTheNewCount() async {
        let (_, model) = make("launch-page")
        let page = Task { await model.whileShown(reason: .settings) }
        await waitUntil("the page's snapshot") { model.snapshot != nil }
        let ok = await model.launch("a", name: "A")
        XCTAssertTrue(ok)
        XCTAssertEqual(model.snapshot?.launchCounts["a"], 1)
        page.cancel()
    }

    /// The window and the page both watch; a launch (from either) leaves the page's counts current.
    func testALaunchWithTheWindowAndThePageWatchingShowsTheNewCount() async {
        let (_, model) = make("launch-both")
        model.present = { _ in ALaunchpadWindowIsOneDoorTests.FakeWindow() }
        model.showLaunchpad()
        let window = Task { await model.whileShown() }
        await waitUntil("the window's snapshot") { model.snapshot != nil }
        let page = Task { await model.whileShown(reason: .settings) }
        try? await Task.sleep(for: .milliseconds(200))
        _ = await model.launch("a", name: "A")
        XCTAssertEqual(model.snapshot?.launchCounts["a"], 1)
        window.cancel(); page.cancel()
    }

    /// An app that went while the window was alone: the launch says gone and the snapshot must lose it (the alone window still refreshes).
    func testAGoneAppLaunchedFromTheAloneWindowIsRefreshedAway() async {
        let (catalog, model) = make("launch-gone")
        model.present = { _ in ALaunchpadWindowIsOneDoorTests.FakeWindow() }
        model.showLaunchpad()
        let window = Task { await model.whileShown() }
        await waitUntil("the window's snapshot") { model.snapshot != nil }
        catalog.reading = CatalogReading(apps: [CatalogApp(id: "b", name: "B", path: "/Applications/b.app")], complete: true)
        _ = await model.launch("a", name: "A")
        XCTAssertEqual(model.snapshot?.apps.keys.sorted(), ["b"], "the gone app is still shown after the launch found it gone")
        window.cancel()
    }

    /// The page is the only watcher while the window's handle is still held (its watch not yet running): a launch must still refresh the page.
    func testALaunchWhileTheWindowIsHeldButNotYetWatchingStillRefreshesThePage() async {
        let (_, model) = make("launch-held")
        model.present = { _ in ALaunchpadWindowIsOneDoorTests.FakeWindow() }
        model.showLaunchpad()
        let page = Task { await model.whileShown(reason: .settings) }
        await waitUntil("the page's snapshot") { model.snapshot != nil }
        _ = await model.launch("a", name: "A")
        XCTAssertEqual(model.snapshot?.launchCounts["a"], 1, "the page shows the count from before the launch")
        page.cancel()
    }
}
