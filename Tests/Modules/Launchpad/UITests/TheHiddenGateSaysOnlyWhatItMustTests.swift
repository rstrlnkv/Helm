import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The gate's banner flag, the Hidden block's id and the log: what is said about a hidden app, and where.
@MainActor final class TheHiddenGateSaysOnlyWhatItMustTests: XCTestCase {
    func testTheUnavailableFlagIsSetOnlyByUnavailableAndClearedByTheNextAsk() async {
        for outcome in [AuthOutcome.failed, .cancelled, .success] {
            let gate = LaunchpadHiddenGate(port: FakeAuthPort(.immediate(outcome)))
            gate.ask(reason: "x") {}
            await gate.settled()
            XCTAssertFalse(gate.unavailable, "\(outcome)")
            gate.lock()
        }
        let unavailable = FakeAuthPort(.immediate(.unavailable))
        let gate = LaunchpadHiddenGate(port: unavailable)
        gate.ask(reason: "x") {}
        await gate.settled()
        XCTAssertTrue(gate.unavailable, "the control: an unavailable Mac sets it")
        gate.lock()
        XCTAssertFalse(gate.unavailable, "a lock clears it")
        gate.ask(reason: "x") {}
        await gate.settled()
        XCTAssertTrue(gate.unavailable)
        let slow = FakeAuthPort(.slow)
        let second = LaunchpadHiddenGate(port: slow)
        second.ask(reason: "x") {}
        await slow.waitForAsks()
        XCTAssertFalse(second.unavailable, "an ask in flight says nothing yet")
        second.lock()
    }

    func testTheHiddenBlockIdIsEveryCategoryBlocksNeighbourAndNoneOfThem() {
        var kinds: [LaunchpadCategoryBlock.Kind] = [.recent, .others]
        kinds += LaunchpadCategory.allCases.map { .category($0) }
        let ids = kinds.map { LaunchpadCategoryBlock(kind: $0, apps: [], launches: 0).id }
        XCTAssertEqual(Set(ids).count, kinds.count, "the control: the blocks' own ids are all different")
        XCTAssertFalse(ids.contains(LaunchpadHiddenBlock.id))
    }

    func testNoLogLineOfTheWholeFlowCarriesAnAppsName() async {
        let name = "Zzyzxsecret"
        let apps = [CatalogApp(id: "h", name: name, path: "/Applications/\(name).app")]
        var layout = LaunchpadLayout(items: [.app("h")])
        layout.hidden = ["h"]
        let snapshot = LaunchpadSnapshot(apps: ["h": apps[0]], order: ["h"], layout: layout, catalogComplete: true, layoutRead: .absent)
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false) }
        let marker = "marker \(UUID().uuidString)"
        HelmLog.shared.info("launchpad", marker)
        for outcome in [AuthOutcome.success, .failed, .cancelled, .unavailable] {
            let fake = FakeAuthPort(.immediate(outcome))
            let gate = LaunchpadHiddenGate(port: fake)
            let state = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1280, height: 800), topSafe: 0), view: .categories, hidden: gate)
            state.setShown(true)
            state.update(snapshot: snapshot)
            state.open(folder: LaunchpadHiddenBlock.id)
            await gate.settled()
            if outcome == .success { XCTAssertEqual(state.folderApps.map(\.name), [name], "the control: the name reached the card") }
            state.shutdown()
        }
        let all = HelmLog.shared.recentEntries().filter { $0.category == "launchpad" }.map(\.message)
        let lines = Array(all.drop { $0 != marker })
        XCTAssertFalse(lines.isEmpty, "the control: the marker was logged")
        XCTAssertTrue(lines.contains { $0.contains("hidden: asked") }, "the control: the log was captured (\(lines.count) lines)")
        XCTAssertFalse(lines.contains { $0.lowercased().contains(name.lowercased()) || $0.contains("/Applications") }, "\(lines)")
    }
}
