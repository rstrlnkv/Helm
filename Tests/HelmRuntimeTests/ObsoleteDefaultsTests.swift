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

    /// Two looks left as settings: how the panel's tabs were labelled and how a module's icon was drawn. `AppSettings.store`
    /// writes under `module.app.`, so this is the spelling the purge has to carry, and a key left behind reads as a live setting.
    func testTheRetiredLookChoicesArePurged() {
        let store = InMemoryKeyValueStore()
        store.set("glyph", forKey: "module.app.tabLabelStyle")
        store.set("plain", forKey: "module.app.sidebarStyle")

        ObsoleteDefaults.purge(from: store)

        XCTAssertNil(store.object(forKey: "module.app.tabLabelStyle"))
        XCTAssertNil(store.object(forKey: "module.app.sidebarStyle"))
    }

    /// Every retired key is namespaced, so the purge can never reach into
    /// another app's or another module's settings.
    func testEveryRetiredKeyIsNamespaced() {
        for key in ObsoleteDefaults.retired {
            XCTAssertTrue(key.hasPrefix("module."), "\(key) is not namespaced")
        }
    }

    /// Where a retired key's constant would be declared, and the name it would carry. A tweak's key is
    /// `module.tweak.<id>.<name>` (its store's namespace is `tweak.<id>`), so reading `tweak` as a module
    /// pointed at `Sources/Modules/Tweak`, which is absent, and the key was skipped as "module gone".
    private static func declaringDirectory(of parts: [Substring]) -> (directory: String, name: String) {
        func pascal(_ word: Substring) -> String { word.prefix(1).uppercased() + word.dropFirst() }
        if parts[1] == "tweak", parts.count >= 4 {
            let tweak = parts[2].split(separator: "-").map(pascal).joined()
            return ("Sources/Tweaks/\(tweak)", parts.dropFirst(3).joined(separator: "."))
        }
        let namespace = parts[1]
        return (namespace == "app" ? "Sources/HelmApp" : "Sources/Modules/\(pascal(namespace))",
                parts.dropFirst(2).joined(separator: "."))
    }

    /// The mapping above, on a fixture: a tweak's key reaches its own folder, and a module's still does.
    func testATweaksKeyIsLookedForInItsOwnFolder() {
        let tweak = Self.declaringDirectory(of: "module.tweak.display-corners.radiusPixels".split(separator: "."))
        XCTAssertEqual(tweak.directory, "Sources/Tweaks/DisplayCorners")
        XCTAssertEqual(tweak.name, "radiusPixels")
        let module = Self.declaringDirectory(of: "module.layout.automatic".split(separator: "."))
        XCTAssertEqual(module.directory, "Sources/Modules/Layout")
        XCTAssertEqual(module.name, "automatic")
        XCTAssertEqual(Self.declaringDirectory(of: "module.app.x".split(separator: ".")).directory, "Sources/HelmApp")
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
    /// **Spelled as a literal counts too.** Most live keys have no constant at all:
    /// `store.string("menuBarIconSize", default: "")` is the whole declaration, so
    /// looking only for `= "name"` let `module.app.menuBarIconSize` join the list
    /// unnoticed (a mutation said so).
    func testNoRetiredKeyStillHasAConstant() throws {
        var checked = 0
        for key in ObsoleteDefaults.retired {
            let parts = key.split(separator: ".")
            guard parts.count >= 3, parts[0] == "module" else {
                return XCTFail("\(key) is not `module.<namespace>.<name>`")
            }
            let (directory, name) = Self.declaringDirectory(of: parts)
            let files = (try? RepoSource.swiftFiles(under: directory)) ?? []
            guard !files.isEmpty else { continue }   // the module itself is gone
            checked += 1
            for path in files {
                let code = SwiftSource.uncommented(
                    try String(contentsOf: RepoSource.root.appendingPathComponent(path),
                               encoding: .utf8))
                XCTAssertFalse(code.contains("\"\(name)\""),
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
}
