import XCTest
@testable import HelmRuntime

/// The two accessors nothing exercised, and what happens when a key holds
/// something the accessor cannot read.
///
/// `NamespacedStore` stores six shapes — Bool, Int, String, [String], Data and
/// [String: Bool] — and the suite covered three. `boolTable` is "the shape
/// three modules now keep" and `data` is where a whole rule set lives, so a
/// wrong answer from either is a settings page that opens empty.
///
/// The point of the wrong-type cases is that they must degrade to the default,
/// not to a crash and not to a lie.
final class NamespacedStoreTypeTests: XCTestCase {
    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "demo", backing: InMemoryKeyValueStore())
    }

    func testBoolTableRoundTrips() {
        let s = store()
        s.set(["com.a": true, "com.b": false], for: "rules")
        XCTAssertEqual(s.boolTable("rules"), ["com.a": true, "com.b": false])
    }

    /// Absent means "no opinion", which is an empty table rather than nil.
    func testBoolTableIsEmptyWhenAbsent() {
        XCTAssertEqual(store().boolTable("never-written"), [:])
    }

    func testDataRoundTrips() {
        let s = store()
        let payload = Data("[{\"bundleID\":\"com.a\"}]".utf8)
        s.set(payload, for: "rulesJSON")
        XCTAssertEqual(s.data("rulesJSON"), payload)
    }

    func testDataIsNilWhenAbsent() {
        XCTAssertNil(store().data("never-written"))
    }

    /// A key holding the wrong shape reads as the default. This is the
    /// already-migrated case: a version stored a JSON string under a key that
    /// now holds Data, or the reverse.
    func testWrongShapesFallBackToTheDefaultRatherThanThrowing() {
        let s = store()
        s.set("not data", for: "a")
        XCTAssertNil(s.data("a"))

        s.set(Data([0x00]), for: "b")
        XCTAssertEqual(s.string("b", default: "fallback"), "fallback")

        s.set(["a", "b"], for: "c")
        XCTAssertEqual(s.boolTable("c"), [:])

        s.set("7", for: "d")
        XCTAssertEqual(s.int("d", default: -1), -1)

        s.set(["only strings"], for: "e")
        XCTAssertEqual(s.stringArray("e"), ["only strings"])
    }

    /// Writing nil removes the key, which is what `ObsoleteDefaults.purge`
    /// relies on: a purged key must read as absent, not as a stored nil.
    func testWritingNilClearsTheKey() {
        let backing = InMemoryKeyValueStore()
        let s = NamespacedStore(namespace: "demo", backing: backing)
        s.set(true, for: "flag")
        s.set(nil, for: "flag")
        XCTAssertNil(backing.object(forKey: "module.demo.flag"))
        XCTAssertTrue(s.bool("flag", default: true))
    }

    /// A key with a separator or a dot of its own must not reach into a
    /// neighbour's namespace.
    func testAKeyCannotClimbOutOfItsNamespace() {
        let backing = InMemoryKeyValueStore()
        NamespacedStore(namespace: "a", backing: backing).set(1, for: "x")
        let intruder = NamespacedStore(namespace: "b", backing: backing)
        XCTAssertEqual(intruder.int("../a.x", default: 0), 0,
                       "the prefix is literal, so a crafted key names a key that does not exist")
    }
}
