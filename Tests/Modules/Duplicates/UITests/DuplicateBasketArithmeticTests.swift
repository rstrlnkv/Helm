import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// What the basket says it will free.
///
/// The bar under the list reads "N · X", and X was the group's single size
/// counted once per ticked path — so a group holding a clone beside its
/// original promised the clone's figure for the original, or the original's for
/// the clone. Copies of one thing need not occupy the same amount; each one
/// carries its own.
@MainActor
final class DuplicateBasketArithmeticTests: XCTestCase {

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
        // In memory: the module's real store is the person's remembered folder.
        let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
        store.set("\(home)/Downloads", for: "folder")
        let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport:
            OneAnswerTransport(groups: groups)), store: store)
        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        return dvm
    }

    /// The clone stays, the real copy goes: what leaves is four megabytes, not
    /// the nothing the clone occupies.
    func testTheBasketCountsEachCopysOwnSize() async {
        let clone = "\(home)/Downloads/clone.bin"
        let real = "\(home)/Downloads/real.bin"
        let dvm = await model([DuplicateGroup(copies: [.init(path: clone, bytes: 0),
                                                      .init(path: real, bytes: 4_000_000)])])
        XCTAssertEqual(dvm.groups.count, 1, "the fixture never reached the view model")

        dvm.toggleBasket(real)

        XCTAssertEqual(dvm.basket, [real])
        XCTAssertEqual(dvm.basketBytes, 4_000_000,
                       "the basket quoted the copy that stays")
    }

    /// The same figure, one path at a time: the basket menu names each copy
    /// beside its own size, and asking the group would print the size of the
    /// copy that stays against every row in the list.
    func testACopysOwnSizeIsAskedOfThatCopy() async {
        let clone = "\(home)/Downloads/clone.bin"
        let real = "\(home)/Downloads/real.bin"
        let dvm = await model([DuplicateGroup(copies: [.init(path: clone, bytes: 0),
                                                      .init(path: real, bytes: 4_000_000)])])

        XCTAssertEqual(dvm.bytes(of: real), 4_000_000)
        XCTAssertEqual(dvm.bytes(of: clone), 0)
        XCTAssertEqual(dvm.bytes(of: "\(home)/Downloads/never-seen.bin"), 0,
                       "a path this search never returned has no size to quote")
    }

    /// And the whole group's promise is the sum of the ones that would go.
    func testWastedIsWhatTheExtrasOccupy() async {
        let dvm = await model([DuplicateGroup(copies: [
            .init(path: "\(home)/Downloads/a.bin", bytes: 1_000_000),
            .init(path: "\(home)/Downloads/b.bin", bytes: 2_000_000),
            .init(path: "\(home)/Downloads/c.bin", bytes: 3_000_000),
        ])])
        XCTAssertEqual(dvm.wastedBytes, 5_000_000)
    }
}
