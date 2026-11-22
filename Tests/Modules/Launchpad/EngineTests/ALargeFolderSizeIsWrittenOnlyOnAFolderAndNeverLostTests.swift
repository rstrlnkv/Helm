import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A folder's size is one flag in its file entry: written only when large, read leniently (anything but `true` is small),
/// carried by every edit that keeps the folder and by a reconcile, refused when stale, and never on an app or a page break.
final class ALargeFolderSizeIsWrittenOnlyOnAFolderAndNeverLostTests: XCTestCase {
    private let apps = ["a", "b", "c", "d", "e"]

    private func engine(_ dir: URL, apps ids: [String]? = nil) -> LaunchpadEngine {
        LaunchpadEngine(catalog: FakeAppCatalog(ids ?? apps), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
    }

    /// A folder "F" of a and b, made large; its id.
    private func largeFolder(_ e: LaunchpadEngine) throws -> UUID {
        _ = e.read(reason: .refresh)
        let made = try XCTUnwrap(e.apply(.makeFolder(drop: "b", onto: "a", name: "F")))
        guard case .folder(let f) = try XCTUnwrap(made.layout.items.first) else { throw XCTSkip("no folder") }
        let sized = try XCTUnwrap(e.apply(.resize(f.id, large: true)))
        guard case .folder(let big) = try XCTUnwrap(sized.layout.items.first) else { throw XCTSkip("no folder") }
        XCTAssertTrue(big.large, "subject: the folder is large")
        return f.id
    }

    private func folder(_ layout: LaunchpadLayout) -> LaunchpadLayout.Folder? {
        for case .folder(let f) in layout.items { return f }
        return nil
    }

    private func decode(_ json: String) throws -> LaunchpadLayout {
        try JSONDecoder().decode(LaunchpadLayout.self, from: Data(json.utf8))
    }

    func testALargeFolderSurvivesASaveAFreshStoreAndAFreshEngine() throws {
        let dir = scratchDirectory("large-roundtrip")
        let id = try largeFolder(engine(dir))
        let again = try XCTUnwrap(folder(engine(dir).read(reason: .refresh).layout))
        XCTAssertEqual(again.id, id)
        XCTAssertTrue(again.large)
        XCTAssertEqual(again.apps, ["a", "b"])
    }

    func testResetArrangementLeavesNoLargeFolder() throws {
        let e = engine(scratchDirectory("large-reset"))
        _ = try largeFolder(e)
        let reset = try XCTUnwrap(e.apply(.resetArrangement))
        XCTAssertNil(folder(reset.layout), "no folder survives a reset, so none is large")
        XCTAssertNil(folder(engine(scratchDirectory("large-reset")).read(reason: .refresh).layout), "and none is stored")
    }

    func testAReconcileThatDropsAnAppKeepsTheSize() throws {
        let dir = scratchDirectory("large-reconcile")
        _ = try largeFolder(engine(dir))
        let f = try XCTUnwrap(folder(engine(dir, apps: ["a", "b", "c"]).read(reason: .refresh).layout))
        XCTAssertTrue(f.large)
        // Three members, one uninstalled: still a large folder of two.
        var three = LaunchpadLayout(items: [.folder(.init(id: id0, name: "F", apps: ["a", "b", "x"], large: true))], hidden: [])
        three = three.reconciled(catalog: ["a", "b"], complete: true)
        XCTAssertEqual(folder(three)?.apps, ["a", "b"], "subject: the uninstalled app went")
        XCTAssertEqual(folder(three)?.large, true)
    }

    private let id0 = UUID()

    func testASmallFoldersFileHasNoKeyAndTheVersionIsOne() throws {
        let small = LaunchpadLayout(items: [.folder(.init(id: id0, name: "F", apps: ["a", "b"])), .app("c")], hidden: [])
        let text = String(decoding: try JSONEncoder().encode(small), as: UTF8.self)
        XCTAssertTrue(text.contains("\"folder\""), "subject: the folder was written")
        XCTAssertFalse(text.contains("large"))
        XCTAssertTrue(text.contains("\"version\":1"))
        let big = LaunchpadLayout(items: [.folder(.init(id: id0, name: "F", apps: ["a", "b"], large: true))], hidden: [])
        let bigText = String(decoding: try JSONEncoder().encode(big), as: UTF8.self)
        XCTAssertTrue(bigText.contains("\"large\":true"))
        XCTAssertTrue(bigText.contains("\"version\":1"))
    }

    func testNoAppOrPageBreakCarriesTheKey() throws {
        let l = try decode(#"{"items":[{"app":"a","large":true},{"pageBreak":true,"large":true},{"app":"b"}]}"#)
        XCTAssertEqual(l.items, [.app("a"), .pageBreak, .app("b")])
        let text = String(decoding: try JSONEncoder().encode(l), as: UTF8.self)
        XCTAssertFalse(text.contains("large"))
    }

    func testAnyValueButTrueReadsSmallAndTheFolderReadsNormally() throws {
        for bad in [#""true""#, "1", "null", "[true]", #"{"x":true}"#, "false"] {
            let l = try decode(#"{"items":[{"app":"n"},{"folder":{"id":"\#(id0.uuidString)","name":"F","apps":["a","b"],"large":\#(bad)}},{"app":"z"}]}"#)
            let f = try XCTUnwrap(folder(l), bad)
            XCTAssertFalse(f.large, bad)
            XCTAssertEqual(f.name, "F", bad)
            XCTAssertEqual(f.apps, ["a", "b"], bad)
            XCTAssertEqual(l.items.count, 3, bad)
        }
        let none = try decode(#"{"items":[{"folder":{"name":"F","apps":["a","b"]}}]}"#)
        XCTAssertEqual(folder(none)?.large, false)
        let yes = try decode(#"{"items":[{"folder":{"name":"F","apps":["a","b"],"large":true}}]}"#)
        XCTAssertEqual(folder(yes)?.large, true, "subject: the key is read at all")
    }

    func testResizeRefusesWhatIsNotThereIsNotAFolderOrAlreadyEqual() throws {
        let dir = scratchDirectory("large-refuse")
        let e = engine(dir)
        let id = try largeFolder(e)
        XCTAssertNil(e.apply(.resize(UUID(), large: true)))
        XCTAssertNil(e.apply(.resize(id, large: true)))
        let small = try XCTUnwrap(e.apply(.resize(id, large: false)))
        XCTAssertEqual(folder(small.layout)?.large, false)
        XCTAssertNil(e.apply(.resize(id, large: false)))
        // An app's id (a bundle id spelled as nothing a folder has) is not a folder.
        XCTAssertNil(LaunchpadLayout(items: [.app("a")], hidden: []).applying(.resize(id0, large: true)))
    }

    func testEditsThatKeepTheFolderKeepItsSize() throws {
        let e = engine(scratchDirectory("large-edits"))
        let id = try largeFolder(e)
        for edit: LaunchpadEdit in [.rename(id, to: "G"), .add("c", toFolder: id, relativeTo: nil, after: true),
                                    .moveInFolder("c", toIndex: 0), .remove("c", fromFolder: id),
                                    .place(id.uuidString, relativeTo: "d", after: true), .move(id.uuidString, toIndex: 0)] {
            let snap = try XCTUnwrap(e.apply(edit), "\(edit)")
            XCTAssertEqual(folder(snap.layout)?.large, true, "\(edit)")
        }
    }
}
