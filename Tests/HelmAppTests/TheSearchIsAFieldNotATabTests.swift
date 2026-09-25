import XCTest
import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
@testable import HelmApp
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The declared content is the proof, not a screenshot of it.**
///
/// The owner's decision, 2026-09-22: the Search tab is removed, and the field
/// that used to sit under it moves onto the window's toolbar on all three
/// remaining tabs. `HelmWindowToolbarChannel` is what `SettingsToolbar`
/// actually reads to build the bar, so what the page declared there — rather
/// than anything rendered from it — is the fact this file holds.
@MainActor
final class TheSearchIsAFieldNotATabTests: XCTestCase {

    private final class Fake: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    func testTheTabsAreThreeAndEachCarriesTheSearchField() async {
        let transport = Fake()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        let fixture = LivePageToolbarFixture(HomebrewSettingsPage(vm: mvm),
                                             selection: .module(HomebrewDescriptor.id.rawValue),
                                             width: 984, height: 520)
        defer { fixture.drop() }
        fixture.settle(25)

        guard let content = fixture.channel.content(for: HomebrewDescriptor.id.rawValue) else {
            return XCTFail("Homebrew never declared anything to the window's toolbar")
        }
        XCTAssertEqual(content.tabs.map(\.id), ["installed", "updates", "health"], """
            \(content.tabs.map(\.id)) — the Search tab must be gone and the other three must \
            keep their order
            """)
        XCTAssertNotNil(content.search, "the search field is missing from every tab's own content")
    }

    /// Adding the tab back is exactly the mutation this file exists to catch.
    func testFourTabsWouldFailThisFile() {
        // Structural, the way `MemoryTrailCoverageTests` reads its own
        // labels: the enum itself is the one place a fourth case could come
        // back, and this reads it rather than the page.
        XCTAssertEqual(HomebrewViewModel.Segment.allCases.count, 3, """
            a fourth segment exists — the case above is no longer the whole \
            of `HelmToolbarTab`'s own list, and this test's own premise is stale
            """)
    }
}
