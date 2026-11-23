import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A catalog read is the module's one bulk walk, so each is asked for once and says why (`read N apps (open)`): the settings page beside the
/// window shares the window's watch, a launch that closes the window refreshes nothing it is about to drop, and the reset of the counts
/// reconciles against the catalog the person last saw. The launch's own fresh read stays (`ALaunchRunsOnlyWhatAFreshReadFindsTests`).
@MainActor
final class TheCatalogIsReadOnlyForWhatNobodyHasAlreadyReadTests: XCTestCase {
    private final class OpeningLauncher: AppLauncherPort, @unchecked Sendable {
        func open(_ url: URL) async -> Bool { true }
    }

    private final class Window: LaunchpadWindowHandle {
        var onClose: (@MainActor () -> Void)?
        func present() {}
        func close() { onClose?() }
        func bringForward() {}
        func beginScrub(_ direction: PinchDirection) {}
        func scrub(to progress: Double) {}
        func endScrub(_ outcome: PinchOutcome) {}
    }

    private func make(_ label: String) -> (catalog: RigCatalog, model: LaunchpadViewModel) {
        let catalog = RigCatalog(["a", "b"])
        let engine = LaunchpadEngine(catalog: catalog, launcher: OpeningLauncher(), store: LayoutStore(directory: scratchDirectory(label)))
        return (catalog, LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())))
    }

    private func settled(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }

    func testASettingsPageBesideTheWindowReadsNothingAndAChangeIsReadOnce() async {
        let (catalog, model) = make("reads-settings")
        let window = Task { await model.whileShown() }
        await waitUntil("the window's snapshot") { model.snapshot != nil }
        XCTAssertEqual(catalog.reads, [.open], "the control: the window's first read, said why")
        let page = Task { await model.whileShown(reason: .settings) }
        await settled()
        XCTAssertEqual(catalog.reads, [.open], "the page joined the window's watch and read nothing")
        catalog.fire()
        await waitUntil("the change is read") { catalog.reads.count == 2 }
        await settled()
        XCTAssertEqual(catalog.reads, [.open, .watch], "one read for the change, not one per watcher")
        window.cancel()
        catalog.fire()
        await waitUntil("the page still watches after the window's watch left") { catalog.reads.count == 3 }
        XCTAssertNotNil(model.snapshot, "the page keeps the snapshot the window's watch left")
        page.cancel()
    }

    func testASettingsPageAloneReadsOnceAtItsStartAndSaysSo() async {
        let (catalog, model) = make("reads-page")
        let page = Task { await model.whileShown(reason: .settings) }
        await waitUntil("the page's snapshot") { model.snapshot != nil }
        XCTAssertEqual(catalog.reads, [.settings])
        page.cancel()
    }

    func testALaunchThatClosesTheWindowReadsOnlyItsOwnCheck() async {
        let (catalog, model) = make("reads-launch")
        model.present = { _ in Window() }
        model.showLaunchpad()
        let watch = Task { await model.whileShown() }
        await waitUntil("the window's snapshot") { model.snapshot != nil }
        let opened = await model.launch("a", name: "A")
        XCTAssertTrue(opened)
        XCTAssertEqual(catalog.reads, [.open, .launch], "the launch's own fresh read, and no refresh for a window that is going")
        watch.cancel()
    }

    func testTheResetOfTheCountsReadsNoCatalogThatWasReadBefore() async {
        let catalog = RigCatalog(["a"])
        let engine = LaunchpadEngine(catalog: catalog, launcher: OpeningLauncher(), store: LayoutStore(directory: scratchDirectory("reads-reset")))
        _ = engine.read(reason: .open)
        _ = engine.resetLaunchCounts()
        XCTAssertEqual(catalog.reads, [.open])
        let fresh = RigCatalog(["a"])
        _ = LaunchpadEngine(catalog: fresh, launcher: OpeningLauncher(), store: LayoutStore(directory: scratchDirectory("reads-reset-2"))).resetLaunchCounts()
        XCTAssertEqual(fresh.reads, [.reset], "the control: with nothing read before, it reads, and says it was the reset")
    }
}
