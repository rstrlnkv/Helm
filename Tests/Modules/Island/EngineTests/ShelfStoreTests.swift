import XCTest
@testable import Module_Island_Engine
@testable import HelmRuntime

/// Fake bookmark port: bookmark data is just the path bytes; resolution can be
/// disabled per path to simulate deleted files.
private struct FakeBookmarks: BookmarkPort {
    var unresolvable: Set<String> = []
    func make(_ url: URL) -> Data? { Data(url.path.utf8) }
    func resolve(_ data: Data) -> URL? {
        let path = String(decoding: data, as: UTF8.self)
        return unresolvable.contains(path) ? nil : URL(fileURLWithPath: path)
    }
}

@MainActor
final class ShelfStoreTests: XCTestCase {
    private func makeStore(port: FakeBookmarks = FakeBookmarks(),
                           backing: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> ShelfStore {
        ShelfStore(store: NamespacedStore(namespace: "island", backing: backing), bookmarks: port)
    }

    func testAddDedupsAndOrdersNewestFirst() {
        let s = makeStore()
        s.add([URL(fileURLWithPath: "/a.txt"), URL(fileURLWithPath: "/b.txt")])
        s.add([URL(fileURLWithPath: "/a.txt")])   // duplicate ignored
        s.add([URL(fileURLWithPath: "/c.txt")])
        XCTAssertEqual(s.items.map(\.name), ["c.txt", "a.txt", "b.txt"])
    }

    func testRemoveAndClear() {
        let s = makeStore()
        s.add([URL(fileURLWithPath: "/a.txt"), URL(fileURLWithPath: "/b.txt")])
        s.remove(s.items[1].id)
        XCTAssertEqual(s.items.map(\.name), ["b.txt"])
        s.clear()
        XCTAssertTrue(s.items.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let backing = InMemoryKeyValueStore()
        let first = makeStore(backing: backing)
        first.add([URL(fileURLWithPath: "/kept.txt")])
        let second = makeStore(backing: backing)
        XCTAssertEqual(second.items.map(\.name), ["kept.txt"])
    }

    func testUnresolvableBookmarkIsKeptAsMissing() {
        let backing = InMemoryKeyValueStore()
        let first = makeStore(backing: backing)
        first.add([URL(fileURLWithPath: "/gone.txt"), URL(fileURLWithPath: "/here.txt")])
        var port = FakeBookmarks(); port.unresolvable = ["/gone.txt"]
        let second = makeStore(port: port, backing: backing)
        XCTAssertEqual(second.items.count, 2)
        XCTAssertTrue(second.items.first { $0.name == "gone.txt" }!.missing)
        XCTAssertFalse(second.items.first { $0.name == "here.txt" }!.missing)
    }
}
