import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A launch counted while a page is shown (the settings page keeps the model's snapshot) reaches that snapshot, so the page's
/// "Reset launch counts" is enabled at once and not after the next change.
@MainActor final class ALaunchRefreshesTheCountsThePageShowsTests: XCTestCase {
    private final class OpeningLauncher: AppLauncherPort, @unchecked Sendable {
        func open(_ url: URL) async -> Bool { true }
    }

    func testAfterALaunchTheModelsSnapshotHoldsTheNewCountSoResetIsEnabled() async throws {
        let dir = scratchDirectory("stale")
        let engine = LaunchpadEngine(catalog: RigCatalog(["a"]), launcher: OpeningLauncher(), store: LayoutStore(directory: dir))
        let model = LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore()))
        let shown = Task { await model.whileShown(reason: .settings) }
        defer { shown.cancel() }
        for _ in 0..<500 where model.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.snapshot?.launchCounts, [:], "the control: a page is shown, nothing counted, so Reset would be disabled")
        let opened = await model.launch("a", name: "A")
        XCTAssertTrue(opened)
        XCTAssertEqual(LaunchCountStore(directory: dir).load().counts, ["a": 1])
        XCTAssertEqual(model.snapshot?.launchCounts, ["a": 1], "the page's Reset reads this")
    }
}
