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
        s.set(42, for: "n"); s.set(["a", "b"], for: "apps"); s.set("x", for: "s")
        XCTAssertEqual(s.int("n", default: 0), 42)
        XCTAssertEqual(s.stringArray("apps"), ["a", "b"])
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

/// The fake and the file must answer the same question the same way.
///
/// Every wrong-type test in the suite is written against `InMemoryKeyValueStore`
/// — "a string where an Int lived answers the module's default" — and what it
/// proves is only worth something if the fake casts the way the real store
/// casts. It did not. `UserDefaults` goes through a plist, so **every** number
/// comes back as an `NSNumber` whatever Swift type went in, and an `NSNumber`
/// casts by value rather than by declaration: `1` under a `Bool` key is `true`
/// in production, `5.0` under an `Int` key is `5`. The fake kept Swift natives,
/// where both of those casts fail — so the tests said "the module refused it"
/// about a value the module accepts.
///
/// The oracle is a plist round trip rather than `UserDefaults.standard`, which
/// no test may touch (3028 keys accumulated in the shared domain), and rather
/// than a hand-written list of expected answers, which would only record what
/// this file's author believed. `PropertyListSerialization` is the same
/// conversion `UserDefaults` performs.
final class InMemoryKeyValueStoreBridgingTests: XCTestCase {

    /// The same value after the trip to a file and back.
    private func throughAPlist(_ value: Any) throws -> Any {
        let data = try PropertyListSerialization.data(fromPropertyList: ["k": value],
                                                      format: .xml, options: 0)
        let read = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap((read as? [String: Any])?["k"])
    }

    /// Asserted through `NamespacedStore`'s own accessors, because those are the
    /// casts that decide what a module reads — and over every combination of
    /// stored value and accessor, so an accessor that happened to agree cannot
    /// carry one that does not.
    func testTheFakeAnswersEveryAccessorTheWayAStoredPlistDoes() throws {
        let stored: [Any] = [true, false, 0, 1, 5, -3, 5.0, 0.5, "5", ["5"]]
        for value in stored {
            let fake = InMemoryKeyValueStore()
            fake.set(value, forKey: "module.demo.k")
            let file = InMemoryKeyValueStore()
            file.raw = ["module.demo.k": try throughAPlist(value)]

            let fromFake = NamespacedStore(namespace: "demo", backing: fake)
            let fromFile = NamespacedStore(namespace: "demo", backing: file)

            XCTAssertEqual(fromFake.bool("k", default: true), fromFile.bool("k", default: true),
                           "a stored \(value) read as a Bool")
            XCTAssertEqual(fromFake.bool("k", default: false), fromFile.bool("k", default: false),
                           "a stored \(value) read as a Bool")
            XCTAssertEqual(fromFake.int("k", default: -99), fromFile.int("k", default: -99),
                           "a stored \(value) read as an Int")
            XCTAssertEqual(fromFake.double("k", default: -99), fromFile.double("k", default: -99),
                           "a stored \(value) read as a Double")
            XCTAssertEqual(fromFake.string("k", default: "—"), fromFile.string("k", default: "—"),
                           "a stored \(value) read as a String")
            XCTAssertEqual(fromFake.stringArray("k"), fromFile.stringArray("k"),
                           "a stored \(value) read as a list of strings")
        }
    }

    /// The two the tester measured, stated as the production answers they are.
    /// The comparison above would be satisfied by two stores that are wrong
    /// together; these say which answer is the right one.
    func testANumberUnderAFlagIsTheFlagAndARealUnderAnIntIsTheInt() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "demo", backing: backing)

        backing.raw = ["module.demo.flag": 1, "module.demo.count": 5.0]

        XCTAssertTrue(store.bool("flag", default: false),
                      "<integer>1</integer> under a Bool key is true in production")
        XCTAssertEqual(store.int("count", default: -1), 5,
                       "<real>5.0</real> under an Int key is 5 in production")
    }

    /// What must not follow from the above: a number is not a string and a
    /// string is not a number. The bridge is `NSNumber`'s, not a coercion of
    /// everything to everything.
    func testAStringUnderANumberIsStillTheDefault() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "demo", backing: backing)

        backing.raw = ["module.demo.count": "5", "module.demo.name": 5]

        XCTAssertEqual(store.int("count", default: -1), -1)
        XCTAssertEqual(store.string("name", default: "—"), "—")
    }

    /// A number inside a container arrives from the file bridged too, so a
    /// table of flags written as `<integer>1</integer>` is a table of flags.
    func testNumbersInsideATableAreBridgedAsWell() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "demo", backing: backing)

        backing.raw = ["module.demo.rules": ["com.a": 1, "com.b": 0]]

        XCTAssertEqual(store.boolTable("rules"), ["com.a": true, "com.b": false])
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
