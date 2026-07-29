import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The one thing this module refuses to do is offer every copy of a file. A
/// button that acts on every group at once is the likeliest place for that
/// refusal to be lost, so it is asserted rather than assumed.
@MainActor
final class BasketAllExtrasTests: XCTestCase {

    private final class OneAnswerTransport: EngineTransport, @unchecked Sendable {
        private let groups: [DuplicateGroup]
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        init(groups: [DuplicateGroup]) { self.groups = groups }
        func send(_ command: EngineCommand) async throws -> Data {
            guard command.name == "find" else { return Data() }
            return (try? JSONEncoder().encode(groups)) ?? Data()
        }
    }

    private var home: String { NSHomeDirectory() }

    private func model(_ groups: [DuplicateGroup]) async -> DuplicatesViewModel {
        let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
        store.set("\(home)/Downloads", for: "folder")
        let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport:
            OneAnswerTransport(groups: groups)), store: store)
        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        return dvm
    }

    /// Under the home directory, because `UserFileScope` judges the real path
    /// and a fixture in `/tmp` would be refused for the wrong reason.
    private func group(_ names: [String], bytes: Int = 2_000_000) -> DuplicateGroup {
        DuplicateGroup(bytes: bytes, paths: names.map { "\(home)/Downloads/\($0)" })
    }

    func testTheCopyThatStaysIsNeverBasketed() async {
        let dvm = await model([group(["a1", "a2", "a3"]), group(["b1", "b2"])])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.contains("\(home)/Downloads/a1"),
                       "the first copy of a group stays")
        XCTAssertFalse(dvm.basket.contains("\(home)/Downloads/b1"))
    }

    func testEveryExtraInEveryGroupIsBasketed() async {
        let dvm = await model([group(["a1", "a2", "a3"]), group(["b1", "b2"])])
        dvm.basketAllExtras()
        XCTAssertEqual(Set(dvm.basket), [
            "\(home)/Downloads/a2", "\(home)/Downloads/a3", "\(home)/Downloads/b2",
        ])
    }

    /// The same scope gate the per-group button applies. A button that baskets
    /// something the engine will refuse is a button that lies.
    func testAPathOutOfScopeIsNotBasketed() async {
        let outside = DuplicateGroup(bytes: 2_000_000, paths: [
            "\(home)/Downloads/a1", "/System/Library/CoreServices/a2",
        ])
        let dvm = await model([outside])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.contains("/System/Library/CoreServices/a2"))
    }

    func testRunningItTwiceDoesNotDoubleTheBasket() async {
        let dvm = await model([group(["a1", "a2"])])
        dvm.basketAllExtras()
        dvm.basketAllExtras()
        XCTAssertEqual(dvm.basket, ["\(home)/Downloads/a2"])
    }

    func testClearEmptiesTheBasketAndTrashesNothing() async {
        let dvm = await model([group(["a1", "a2"])])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.isEmpty)
        dvm.clearBasket()
        XCTAssertTrue(dvm.basket.isEmpty)
        XCTAssertEqual(dvm.removedCount, 0, "clearing is not deleting")
    }
}
