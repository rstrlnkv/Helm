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
