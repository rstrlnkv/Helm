import XCTest
import HelmTestSupport

/// **Writing the setting is half the act; the engine has to be told to re-read.**
///
/// `LayoutEngine` does not watch the store. It holds `exceptions`, `automatic`,
/// `appRules` and the rest in fields and refills them in `reloadSettings`,
/// which runs on `activate()` and on `LayoutCommand.settingsChanged` and
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

    /// Read from the tree rather than from a build product: this asserts about
    /// what is written, and a stale module would answer for the wrong source.
    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepoSource.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The scan is only worth anything while it is reading the writers, so it
    /// opens by counting them. A rename that empties this list would otherwise
    /// leave a test passing over nothing — the family CLAUDE.md collects under
    /// «a check that cannot fail is not a check».
    func testEveryVerbThatWritesASettingAlsoSendsSettingsChanged() throws {
        let file = "Sources/Modules/Layout/UI/LayoutDescriptor.swift"
        let text = SwiftSource.uncommented(try source(file))
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
            XCTAssertTrue(body.contains("LayoutCommand.settingsChanged"),
                          "\(name) in \(file) writes a setting and never tells the engine to "
                          + "re-read it, so the person's change does not reach the module")
        }
    }

    /// And the same for the two writers one target over, which is where the
    /// pattern this scan defends was already correct.
    func testThePageAndTheListsWindowAnnounceTheirWritesToo() throws {
        for file in ["Sources/Modules/Layout/UI/LayoutSettingsPage.swift",
                     "Sources/Modules/Layout/UI/LayoutLists.swift"] {
            let text = SwiftSource.uncommented(try source(file))
            guard let write = SwiftSource.body(of: "write", in: text) else {
                return XCTFail("\(file) has no `write` — the one door its rows go through is gone")
            }
            XCTAssertTrue(write.contains("store.set("), "\(file): `write` no longer writes")
            XCTAssertTrue(write.contains("settingsChanged") || write.contains("announce()"),
                          "\(file): `write` stores the value and never tells the engine")
        }
    }
}
