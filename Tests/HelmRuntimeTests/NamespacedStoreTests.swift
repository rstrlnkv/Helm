import XCTest
@testable import HelmRuntime

final class NamespacedStoreTests: XCTestCase {
    func makeStore() -> NamespacedStore {
        NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
    }
    func test_keys_are_namespaced() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "keep-awake", backing: backing)
        store.set(true, for: "clamshellEnabled")
        XCTAssertEqual(backing.raw["module.keep-awake.clamshellEnabled"] as? Bool, true)
    }
    func test_roundtrip_bool_int_string_array() {
        let s = makeStore()
        s.set(42, for: "n"); s.set(["a","b"], for: "apps"); s.set("x", for: "s")
        XCTAssertEqual(s.int("n", default: 0), 42)
        XCTAssertEqual(s.stringArray("apps"), ["a","b"])
        XCTAssertEqual(s.string("s", default: ""), "x")
    }
    func test_defaults_returned_when_missing() {
        XCTAssertEqual(makeStore().int("missing", default: 20), 20)
        XCTAssertFalse(makeStore().bool("missing", default: false))
    }
    func test_two_namespaces_do_not_collide() {
        let backing = InMemoryKeyValueStore()
        NamespacedStore(namespace: "a", backing: backing).set(1, for: "k")
        NamespacedStore(namespace: "b", backing: backing).set(2, for: "k")
        XCTAssertEqual(NamespacedStore(namespace: "a", backing: backing).int("k", default: 0), 1)
        XCTAssertEqual(NamespacedStore(namespace: "b", backing: backing).int("k", default: 0), 2)
    }
}

/// The store every engine's tests are given, under the traffic those engines
/// actually make.
///
/// `InMemoryKeyValueStore` stands in for `UserDefaults`, which is safe to touch
/// from any thread — and the engines it is handed to read their own state from
/// their own queues while the test that owns them writes from its. As a bare
/// dictionary it was neither: two threads in a Swift `Dictionary` is undefined
/// behaviour, not a race with a bad outcome, and it took the Autopilot bundle
/// down with no assertion and no message about once in thirty runs under load.
/// The thread sanitizer named it: `AutopilotSealTests.plant` against
/// `InMemoryKeyValueStore.object(forKey:)` on the engine's queue.
final class InMemoryKeyValueStoreThreadingTests: XCTestCase {

    /// Written from one thread while another reads, which is the shape of every
    /// engine test that plants a value behind a running engine.
    func testValuesWrittenWhileTheStoreIsBeingReadAllArrive() {
        let store = InMemoryKeyValueStore()
        let count = 2_000
        let written = expectation(description: "written")
        let read = expectation(description: "read")

        DispatchQueue.global().async {
            for i in 0..<count { store.set(i, forKey: "k\(i)") }
            written.fulfill()
        }
        DispatchQueue.global().async {
            for i in 0..<count { _ = store.object(forKey: "k\(i)") }
            read.fulfill()
        }

        wait(for: [written, read], timeout: 30)
        XCTAssertEqual((0..<count).compactMap { store.object(forKey: "k\($0)") as? Int },
                       Array(0..<count), "a write was lost to a concurrent read")
    }

    /// And the whole dictionary, which the tests reach through `raw`.
    func testTheWholeMapCanBeReplacedWhileTheStoreIsBeingRead() {
        let store = InMemoryKeyValueStore()
        store.set(0, forKey: "k")
        let replaced = expectation(description: "replaced")
        let read = expectation(description: "read")

        DispatchQueue.global().async {
            for i in 0..<2_000 { store.raw = ["k": i] }
            replaced.fulfill()
        }
        DispatchQueue.global().async {
            for _ in 0..<2_000 { _ = store.object(forKey: "k") }
            read.fulfill()
        }

        wait(for: [replaced, read], timeout: 30)
        XCTAssertEqual(store.object(forKey: "k") as? Int, 1_999)
    }
}

/// Writes must announce themselves: panel tiles and settings pages read the same
/// keys, and without a signal one side keeps showing a stale value.
final class NamespacedStoreChangeNotificationTests: XCTestCase {
    func testSetPostsChangeNotificationWithNamespacedKey() {
        let store = NamespacedStore(namespace: "demo", backing: InMemoryKeyValueStore())
        var received: String?
        let token = NotificationCenter.default.addObserver(
            forName: .helmStoreChanged, object: nil, queue: nil
        ) { note in received = note.object as? String }
        defer { NotificationCenter.default.removeObserver(token) }

        store.set(true, for: "flag")

        XCTAssertEqual(received, "module.demo.flag")
    }
}
