import XCTest
import HelmTestSupport
@testable import HelmUI

/// A key written twice in one string catalog, which nothing else can see.
///
/// A JSON reader keeps the **last** entry of a repeated key and says nothing, and the build passes the
/// file (`SwiftPM` ran it: exit 0). `ModuleCatalogs` reads the same collapsed dictionary and finds every
/// symbol present, and English shows nothing at all. Which of the two translations shipped was decided
/// by which one was further down the file. The `.strings` files had eight of them for exactly this
/// reason: `General`, `Media`, `Network`, `Paused`, `Show`, `Show Quit button`, `Show Settings button`
/// and `System`, each re-added by a later feature under a translation written for something else.
///
/// So this reads the catalogs as **text**, which is the one way to see an entry the loader has already
/// thrown away. **A duplicate key is the rule of different English for a second meaning, wearing a
/// disguise**: two entries under one key are two meanings somebody translated separately.
final class OneEntryPerKeyTests: XCTestCase {

    /// The keys of the catalog's `"strings"` object, in file order, with their escapes resolved.
    /// A small scanner: it follows strings (so a brace inside one is not a brace), the depth of `{`
    /// and `[`, and the key last seen at depth one (the root's own keys: `sourceLanguage`, `strings`).
    static func symbolKeys(ofCatalog text: String) -> [String] {
        let characters = Array(text)
        var keys: [String] = []
        var depth = 0
        var rootKey = ""
        var index = 0
        while index < characters.count {
            let c = characters[index]
            if c == "\"" {
                var end = index + 1
                while end < characters.count, characters[end] != "\"" {
                    end += characters[end] == "\\" ? 2 : 1
                }
                let literal = String(characters[(index + 1)..<min(end, characters.count)])
                var after = end + 1
                while after < characters.count, characters[after].isWhitespace { after += 1 }
                if after < characters.count, characters[after] == ":" {
                    let key = (try? JSONSerialization.jsonObject(with: Data("\"\(literal)\"".utf8),
                                                                 options: .fragmentsAllowed) as? String) ?? literal
                    if depth == 1 { rootKey = key }
                    if depth == 2, rootKey == "strings" { keys.append(key) }
                }
                index = end + 1
                continue
            }
            if c == "{" || c == "[" { depth += 1 }
            if c == "}" || c == "]" { depth -= 1 }
            index += 1
        }
        return keys
    }

    func testTheReadingSeesARepeatedKeyAndOnlyTheSymbols() {
        let text = """
        { "sourceLanguage" : "en", "strings" : {
            "show" : { "localizations" : { "en" : { "stringUnit" : { "value" : "Show { it }" } } } },
            "say \\"hi\\"" : { "comment" : "x" },
            "show" : { "localizations" : { "ru" : { "stringUnit" : { "value" : "Показать" } } } }
          }, "version" : "1.0" }
        """
        XCTAssertEqual(Self.symbolKeys(ofCatalog: text), ["show", "say \"hi\"", "show"])
    }

    func testNoSymbolIsWrittenTwiceInOneCatalog() throws {
        let catalogs = try ModuleCatalogs.all()
        XCTAssertGreaterThanOrEqual(catalogs.count, 12, "only \(catalogs.count) catalog(s) were read")
        XCTAssertTrue(catalogs.contains { $0.module == "HelmUI" }, "the kit's catalog was not read")
        var offenders: [String] = []
        for catalog in catalogs {
            let text = try String(contentsOf: RepoSource.root.appendingPathComponent(catalog.path), encoding: .utf8)
            let keys = Self.symbolKeys(ofCatalog: text)
            // Read as text, checked against the file read as data: a scanner that recognised nothing
            // would report no repeat and pass for ever.
            let data = try Data(contentsOf: RepoSource.root.appendingPathComponent(catalog.path))
            let loaded = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"]
                                       as? [String: Any], "\(catalog.path) has no strings object")
            XCTAssertEqual(Set(keys), Set(loaded.keys),
                           "\(catalog.path): the keys read as text are not the keys the loader sees, "
                           + "so this check is measuring its own scanner")
            let counts = keys.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            for (key, count) in counts where count > 1 {
                offenders.append("  \(catalog.path): \"\(key)\" written \(count) times")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) symbol(s) are written more than once. The loader keeps the last "
                      + "and says nothing, so which translation ships is decided by file order — give each "
                      + "meaning its own key, or delete the entry that is not the one:\n"
                      + offenders.sorted().joined(separator: "\n"))
    }
}
