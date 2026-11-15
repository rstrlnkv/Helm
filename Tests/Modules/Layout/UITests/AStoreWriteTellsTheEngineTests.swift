import XCTest
import HelmTestSupport

/// **Writing the setting is half the act; the engine has to be told to re-read.**
///
/// `LayoutEngine` does not watch the store. It holds `exceptions`, `automatic`,
/// `appRules` and the rest in fields and refills them in `reloadSettings`,
/// which runs on `activate()` and on `settingsChanged()` and
/// nowhere else — there is no bridge anywhere in the app turning a store write
/// into that command. So a write with no send is a setting the person changed
/// and the module did not.
///
/// `LayoutDescriptor.never` shipped exactly that: the panel tile's «Never this
/// word» wrote the list and stopped, so the word went on being converted until
/// some *other* setting was saved or the app was relaunched. Its neighbour
/// `automatic`, four lines below, did both halves, and the doc comment standing
/// over the pair claimed both did.
///
/// **A source scan, because the defect is invisible at runtime from inside a
/// test:** the write succeeds, the store holds the right list, and only a
/// living engine in another target would notice nothing followed. The pairing
/// is a property of the text, so the text is what is read.
final class AStoreWriteTellsTheEngineTests: XCTestCase {

    /// The scan is only worth anything while it is reading the writers, so it
    /// opens by counting them. A rename that empties this list would otherwise
    /// leave a test passing over nothing — the family (ARCHITECTURE.md § What makes a check) collects under
    /// «a check that cannot fail is not a check».
    func testEveryVerbThatWritesASettingAlsoSendsSettingsChanged() throws {
        let file = "Sources/Modules/Layout/UI/LayoutDescriptor.swift"
        let text = SwiftSource.uncommented(try RepoSource.text(of: file))
        let writers = SwiftSource.functionBodies(in: text)
            .map { body -> (String, String) in
                let characters = Array(text)
                return (body.name, String(characters[(body.open + 1)..<body.close]))
            }
            .filter { $0.1.contains("store.set(") }

        XCTAssertGreaterThanOrEqual(writers.count, 2,
                                    "the scan found \(writers.count) verbs writing a setting in "
                                    + "\(file) — it is reading the wrong file or the wrong shape")

        for (name, body) in writers {
            XCTAssertTrue(body.contains(".settingsChanged()"),
                          "\(name) in \(file) writes a setting and never tells the engine to "
                          + "re-read it, so the person's change does not reach the module")
        }
    }

    /// And the same for the two writers one target over, which is where the
    /// pattern this scan defends was already correct.
    func testThePageAndTheListsWindowAnnounceTheirWritesToo() throws {
        for file in ["Sources/Modules/Layout/UI/LayoutSettingsPage.swift",
                     "Sources/Modules/Layout/UI/LayoutLists.swift"] {
            let text = SwiftSource.uncommented(try RepoSource.text(of: file))
            guard let write = SwiftSource.body(of: "write", in: text) else {
                return XCTFail("\(file) has no `write` — the one door its rows go through is gone")
            }
            XCTAssertTrue(write.contains("store.set("), "\(file): `write` no longer writes")
            XCTAssertTrue(write.contains("settingsChanged") || write.contains("announce()"),
                          "\(file): `write` stores the value and never tells the engine")
        }
    }

    /// `write` is only the one door while every row goes through it: a row that
    /// calls `store.set` itself stores the value and leaves the engine untold.
    func testEverySwitchRowGoesThroughWrite() throws {
        let file = "Sources/Modules/Layout/UI/LayoutSettingsPage.swift"
        let text = SwiftSource.uncommented(try RepoSource.text(of: file))
        let rows = SwiftSource.bodiesNamed("switchRow", in: text)
        XCTAssertFalse(rows.isEmpty, "\(file) has no `switchRow` — the scan is reading the wrong shape")
        for body in rows {
            XCTAssertTrue(body.contains("write("), "\(file): `switchRow` no longer goes through `write`")
            XCTAssertFalse(body.contains("store.set("), "\(file): `switchRow` writes the store itself")
        }
    }

    /// The tile's size is what makes a 1×1 and a 2×1 differ; a `Fixed` that
    /// drew one size for both would shrink the wide tile and nothing else would notice.
    func testTheFixedWidgetPassesItsSizeToTheTile() throws {
        let file = "Sources/Modules/Layout/UI/LayoutWidgets.swift"
        let text = SwiftSource.uncommented(try RepoSource.text(of: file))
        let characters = Array(text)
        let bodies = SwiftSource.typeBodies(in: text).filter { $0.name == "Fixed" }
            .map { String(characters[($0.open + 1)..<$0.close]) }
        XCTAssertFalse(bodies.isEmpty, "\(file) has no `Fixed` — the scan is reading the wrong shape")
        for body in bodies {
            XCTAssertTrue(body.contains("size: size"), "\(file): `Fixed` does not pass its `size` on")
        }
    }
}
