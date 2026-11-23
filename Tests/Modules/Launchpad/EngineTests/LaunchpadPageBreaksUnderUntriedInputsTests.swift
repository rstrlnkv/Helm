import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// What nobody fed the page breaks and the anchored drops: a file of ten thousand breaks, a break first, last and in a row in
/// a stored file, ids that collide across kinds, names cut in the middle of a space, and a long run of random edits that must
/// leave every app once, no break at an edge or in a row, and a layout that normalising again does not change.
final class LaunchpadPageBreaksUnderUntriedInputsTests: XCTestCase {
    private func shape(_ l: LaunchpadLayout?) -> [String]? {
        l?.items.map { item in
            switch item {
            case .app(let id): id
            case .folder(let f): "[" + f.apps.joined(separator: ",") + "]"
            case .pageBreak: "|"
            }
        }
    }

    private func load(_ json: String) throws -> LayoutRead {
        let dir = scratchDirectory("breaks-odd")
        try Data(json.utf8).write(to: dir.appendingPathComponent("layout.json"))
        return LayoutStore(directory: dir).load()
    }

    // MARK: The stored file

    func testTenThousandBreaksInAFileAreBoundedAndTheAppsAmongThemSurvive() throws {
        let breaks = String(repeating: #"{"pageBreak":true},"#, count: 10_000)
        guard case .loaded(let l) = try load(#"{"version":1,"items":[\#(breaks){"app":"a"},{"pageBreak":true},{"app":"b"}],"hidden":[]}"#) else { return XCTFail("not loaded") }
        XCTAssertLessThanOrEqual(l.items.count, 5_000, "bounded by the ceiling, whatever the file holds")
        let n = l.normalized()
        XCTAssertEqual(shape(n), [], "five thousand breaks and nothing else is no page")
        // The engine puts the apps in catalog order after them: a layout that was all breaks is an empty arrangement.
        XCTAssertEqual(shape(n.reconciled(catalog: ["a", "b"], complete: true)), ["a", "b"])
    }

    // MARK: Edits at a break

    func testEveryDestinationWithTheDraggedItemAsItsOwnAnchorMeansNothing() {
        let f = LaunchpadLayout.Folder(id: UUID(), name: "F", apps: ["x", "y"])
        let l = LaunchpadLayout(items: [.app("a"), .pageBreak, .folder(f), .app("b")])
        for id in ["a", "b", f.id.uuidString] {
            XCTAssertNil(l.edit(dropping: id, source: .top, destination: .beside(id, after: true), folderName: "N"), id)
            XCTAssertNil(l.edit(dropping: id, source: .top, destination: .beside(id, after: false), folderName: "N"), id)
            XCTAssertNil(l.edit(dropping: id, source: .top, destination: .onto(id), folderName: "N"), id)
        }
        XCTAssertNil(l.edit(dropping: "x", source: .folder(f.id), destination: .intoFolder(f.id, relativeTo: "x", after: true), folderName: "N"))
        XCTAssertNil(l.edit(dropping: "x", source: .folder(f.id), destination: .intoFolder(f.id, relativeTo: "x", after: false), folderName: "N"))
    }

    func testAnAppDraggedAcrossABreakJoinsTheOtherPageAndTheOnlyAppOfAPageTakesItsPageWithIt() {
        let l = LaunchpadLayout(items: [.app("a"), .app("b"), .pageBreak, .app("c"), .pageBreak, .app("d")])
        func drop(_ id: String, _ d: LaunchpadDropDestination) -> [String]? {
            shape(l.edit(dropping: id, source: .top, destination: d, folderName: "N").flatMap { l.applying($0) })
        }
        XCTAssertEqual(drop("b", .beside("c", after: false)), ["a", "|", "b", "c", "|", "d"], "before the first of the next page")
        XCTAssertEqual(drop("c", .beside("b", after: true)), ["a", "b", "c", "|", "d"], "the page of one is gone with its only app")
        XCTAssertEqual(drop("a", .beside("d", after: true)), ["b", "|", "c", "|", "d", "a"])
        XCTAssertEqual(drop("c", .newPage), ["a", "b", "|", "d", "|", "c"], "a middle page's only app to a page at the end")
        XCTAssertNil(drop("d", .newPage), "already alone on the last page")
    }

    func testAMemberDroppedBesideItsOwnFoldersDissolvingTwoAppFolderLeavesBothAppsOnce() {
        let f = LaunchpadLayout.Folder(id: UUID(), name: "F", apps: ["x", "y"])
        let l = LaunchpadLayout(items: [.app("a"), .folder(f), .pageBreak, .app("b")])
        for after in [true, false] {
            let r = l.edit(dropping: "x", source: .folder(f.id), destination: .beside(f.id.uuidString, after: after), folderName: "N").flatMap { l.applying($0) }
            XCTAssertEqual(shape(r), after ? ["a", "y", "x", "|", "b"] : ["a", "x", "y", "|", "b"], "after \(after)")
        }
    }

    // MARK: Names

    func testANameCutAtTheCeilingIsStillTrimmed() throws {
        let id = UUID()
        let l = LaunchpadLayout(items: [.folder(.init(id: id, name: "F", apps: ["x", "y"]))])
        let typed = String(repeating: "a", count: LaunchpadLimits.maxFolderName - 1) + " tail"
        let renamed = try XCTUnwrap(l.applying(.rename(id, to: typed)))
        guard case .folder(let f) = renamed.items.first else { return XCTFail("no folder") }
        XCTAssertEqual(f.name, f.name.trimmingCharacters(in: .whitespacesAndNewlines), "the name a person typed is trimmed after the cut too: \(f.name.debugDescription)")
        XCTAssertLessThanOrEqual(f.name.count, LaunchpadLimits.maxFolderName)
    }

    // MARK: One id for two kinds

    func testAnAppWhoseIdIsAFoldersIdIsTheAppForAnAppDropAndNeverTheFolder() {
        let f = LaunchpadLayout.Folder(id: UUID(), name: "F", apps: ["x", "y"])
        // A bundle id is whatever a bundle says; this one is spelled as a folder's identity.
        let l = LaunchpadLayout(items: [.folder(f), .app(f.id.uuidString), .app("b")])
        let r = l.edit(dropping: f.id.uuidString, source: .top, destination: .beside("b", after: true), folderName: "N").flatMap { l.applying($0) }
        // Either the app moved (folder stays first) or the edit is refused as ambiguous; the folder must not be the one that moved.
        if let r { XCTAssertEqual(r.items.first, .folder(f), "the folder moved when the app was dropped: \(shape(r) ?? [])") }
    }

    func testAnAppWhoseIdIsAFoldersIdMakesAFolderOrJoinsOneLikeAnyAppAndLeavesTheRealFolderAlone() throws {
        let f = LaunchpadLayout.Folder(id: UUID(), name: "F", apps: ["x", "y"])
        let l = LaunchpadLayout(items: [.folder(f), .app(f.id.uuidString), .app("b")])
        // Onto an app: a new folder of the two, not a reorder of the real folder.
        let onto = try XCTUnwrap(l.edit(dropping: f.id.uuidString, source: .top, destination: .onto("b"), folderName: "N"), "an app dropped onto an app makes a folder")
        let made = try XCTUnwrap(l.applying(onto))
        XCTAssertEqual(shape(made), ["[x,y]", "[b," + f.id.uuidString + "]"], "the app (not the folder) went into the new folder")
        // Into the real folder: an app joins it.
        let into = try XCTUnwrap(l.edit(dropping: f.id.uuidString, source: .top, destination: .intoFolder(f.id, relativeTo: nil, after: true), folderName: "N"), "an app may join a folder")
        XCTAssertEqual(shape(l.applying(into)), ["[x,y," + f.id.uuidString + "]", "b"])
    }

    // MARK: Random runs

    func testAThousandRandomEditsOverPagesKeepEveryAppOnceAndNoBreakAtAnEdgeOrInARow() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        let apps = (0..<14).map { "app\($0)" }
        var l = LaunchpadLayout(items: apps.prefix(6).map { .app($0) } + [.pageBreak] + apps.dropFirst(6).map { .app($0) }, hidden: [])
        var applied = 0
        for step in 0..<1000 {
            let f = l.items.compactMap { item -> UUID? in if case .folder(let f) = item { f.id } else { nil } }
            let ids = apps + f.map(\.uuidString) + ["ghost", ""]
            let id = ids[next(ids.count)], anchor = ids[next(ids.count)]
            let sources: [LaunchpadDropSource] = [.top] + f.map { .folder($0) }
            var destinations: [LaunchpadDropDestination] = [.newPage, .beside(anchor, after: next(2) == 0), .onto(anchor)]
            if let target = f.first { destinations.append(.intoFolder(target, relativeTo: anchor, after: next(2) == 0)) }
            guard let edit = l.edit(dropping: id, source: sources[next(sources.count)], destination: destinations[next(destinations.count)], folderName: "N"),
                  let after = l.applying(edit) else { continue }
            XCTAssertNotEqual(after, l.normalized(), "step \(step): an edit that was named changes the layout")
            XCTAssertEqual(after, after.normalized(), "step \(step): normalising twice is normalising once")
            XCTAssertNotEqual(after.items.first, .pageBreak, "step \(step)")
            XCTAssertNotEqual(after.items.last, .pageBreak, "step \(step)")
            XCTAssertFalse(zip(after.items, after.items.dropFirst()).contains { $0 == .pageBreak && $1 == .pageBreak }, "step \(step)")
            var seen: [String] = []
            for item in after.items {
                switch item {
                case .app(let a): seen.append(a)
                case .folder(let fo): seen += fo.apps
                case .pageBreak: break
                }
            }
            XCTAssertEqual(seen.sorted(), apps.sorted(), "step \(step): every app once")
            l = after
            applied += 1
        }
        XCTAssertGreaterThan(applied, 100, "the run really edited: \(applied)")
    }
}
