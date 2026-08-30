import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// Settings outlive the features that wrote them. A key left behind by a
/// removed feature is invisible clutter that later reads as a real setting.
final class ObsoleteDefaultsTests: XCTestCase {
    func testRemovesRetiredKeys() {
        let store = InMemoryKeyValueStore()
        store.set("list", forKey: "module.app.panelLayout")
        store.set(["disk"], forKey: "module.app.moduleOrder")

        ObsoleteDefaults.purge(from: store)

        XCTAssertNil(store.object(forKey: "module.app.panelLayout"))
        XCTAssertNotNil(store.object(forKey: "module.app.moduleOrder"),
                        "a live setting must survive the purge")
    }

    func testPurgingTwiceIsHarmless() {
        let store = InMemoryKeyValueStore()
        ObsoleteDefaults.purge(from: store)
        ObsoleteDefaults.purge(from: store)
        XCTAssertNil(store.object(forKey: "module.app.panelLayout"))
    }

    /// Every retired key is namespaced, so the purge can never reach into
    /// another app's or another module's settings.
    func testEveryRetiredKeyIsNamespaced() {
        for key in ObsoleteDefaults.retired {
            XCTAssertTrue(key.hasPrefix("module."), "\(key) is not namespaced")
        }
    }

    /// **A retired key's constant must be gone**, because the purge really
    /// deletes and it runs at every launch.
    ///
    /// The list is written by hand — it has to be, since nothing in the tree
    /// remembers a constant that was removed — so the half that *can* be tied
    /// to the tree is the other direction: no name on it may still be declared
    /// as a key by the code that owns its namespace. Retire
    /// `module.layout.automatic` by a slip and every launch would quietly
    /// switch the module off for everyone who had it on, with no error
    /// anywhere.
    ///
    /// **The declaration, not the write.** Two earlier versions of this scan
    /// tried to find the *write* and could not: every write in this codebase
    /// names a constant (`store.set(on, for: LayoutKey.automatic)`, and the
    /// page's own `write(value, LayoutKey.automatic)`), so a scan for
    /// `for: "automatic"` matched nothing at all and passed while three live
    /// keys sat on the retired list. Three mutations said so, one after
    /// another. The declaration is the thing that is actually spellable, and it
    /// is also the stronger rule: a key whose feature is gone has no reason to
    /// keep a constant.
    ///
    /// The exception is a key still read *once* by the migration that carries
    /// its value somewhere new before the purge takes it. There is one, it is
    /// named here with its reason, and adding a second should be an argument
    /// rather than an edit.
    func testNoRetiredKeyStillHasAConstant() throws {
        /// Retired *and* still declared, on purpose. `PanelFooterSetting` reads
        /// this key once at launch to unfold the three switches it became, and
        /// `AppSettings.migrateAndPurge` is one function so the read cannot
        /// happen after the delete.
        let migrating: Set<String> = ["module.app.showPanelFooter"]

        var checked = 0
        for key in ObsoleteDefaults.retired where !migrating.contains(key) {
            let parts = key.split(separator: ".")
            guard parts.count >= 3, parts[0] == "module" else {
                return XCTFail("\(key) is not `module.<namespace>.<name>`")
            }
            let namespace = String(parts[1])
            let name = parts.dropFirst(2).joined(separator: ".")
            let directory = namespace == "app"
                ? "Sources/HelmApp"
                : "Sources/Modules/\(namespace.prefix(1).uppercased() + namespace.dropFirst())"
            let files = (try? RepoSource.swiftFiles(under: directory)) ?? []
            guard !files.isEmpty else { continue }   // the module itself is gone
            checked += 1
            for path in files {
                let code = SwiftSource.uncommented(
                    try String(contentsOf: RepoSource.root.appendingPathComponent(path),
                               encoding: .utf8))
                XCTAssertFalse(code.contains("= \"\(name)\""),
                               "\(key) is on the retired list — the purge deletes it at every "
                               + "launch — and \(path) still declares `\(name)` as a key. Either "
                               + "the constant is dead and should go, or the setting is live and "
                               + "is being thrown away for everyone who set it.")
            }
        }
        XCTAssertGreaterThan(checked, 3,
                             "only \(checked) retired keys had a namespace with source to check "
                             + "against; the directory names this derives are wrong")
    }

    /// The Island module was rolled back, and its settings stayed behind.
    func testIslandKeysAreRetired() {
        let store = InMemoryKeyValueStore()
        store.set(true, forKey: "module.island.enabled")
        store.set(["a"], forKey: "module.island.shelfBookmarks")
        ObsoleteDefaults.purge(from: store)
        XCTAssertNil(store.object(forKey: "module.island.enabled"))
        XCTAssertNil(store.object(forKey: "module.island.shelfBookmarks"))
    }
}
