import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// What a drop means, asked of the layout alone: the edit it names by **anchor ids**, and the layout that edit leaves.
/// The drag, the gap and the dwell are the window's and are judged by eye.
final class LaunchpadDropEditTests: XCTestCase {
    private func apps(_ ids: [String]) -> LaunchpadLayout { LaunchpadLayout(items: ids.map { .app($0) }) }
    private func folder(_ apps: [String]) -> LaunchpadLayout.Folder { LaunchpadLayout.Folder(id: UUID(), name: "F", apps: apps) }

    /// The layout after the drop; nil when the drop means nothing or is refused.
    private func dropped(_ l: LaunchpadLayout, _ id: String, from source: LaunchpadDropSource = .top,
                         _ destination: LaunchpadDropDestination) -> LaunchpadLayout? {
        l.edit(dropping: id, source: source, destination: destination, folderName: "N").flatMap { l.applying($0) }
    }

    /// Top level as ids, a page break as "|", a folder as its members in brackets.
    private func shape(_ l: LaunchpadLayout?) -> [String]? {
        l?.items.map { item in
            switch item {
            case .app(let id): id
            case .folder(let f): "[" + f.apps.joined(separator: ",") + "]"
            case .pageBreak: "|"
            }
        }
    }

    // MARK: Beside: anchors, not indices

    func testBesideLandsNextToTheAnchorWhicheverSideTheDraggedOneCameFrom() {
        let l = apps(["a", "b", "c", "d", "e"])
        XCTAssertEqual(shape(dropped(l, "a", .beside("d", after: false))), ["b", "c", "a", "d", "e"])
        XCTAssertEqual(shape(dropped(l, "a", .beside("d", after: true))), ["b", "c", "d", "a", "e"])
        XCTAssertEqual(shape(dropped(l, "e", .beside("b", after: false))), ["a", "e", "b", "c", "d"])
        XCTAssertEqual(shape(dropped(l, "e", .beside("b", after: true))), ["a", "b", "e", "c", "d"])
    }

    func testTheAnchorHoldsWhenHiddenAndMissingEntriesStandBetween() {
        // The window draws only some of the layout's entries, so an anchor is an id, and the neighbours in the layout may be others.
        let f = folder(["x", "y"])
        let l = LaunchpadLayout(items: [.app("a"), .pageBreak, .folder(f), .app("c"), .app("e")], hidden: ["h"])
        XCTAssertEqual(shape(dropped(l, "e", .beside("c", after: false))), ["a", "|", "[x,y]", "e", "c"])
        XCTAssertEqual(shape(dropped(l, "a", .beside("c", after: true))), ["[x,y]", "c", "a", "e"], "the break a leaves in front is dropped")
    }

    func testADropThatLeavesTheLayoutAsItIsMeansNothing() {
        let l = apps(["a", "b", "c"])
        XCTAssertNil(l.edit(dropping: "b", source: .top, destination: .beside("c", after: false), folderName: "F"))
        XCTAssertNil(l.edit(dropping: "b", source: .top, destination: .beside("a", after: true), folderName: "F"))
        XCTAssertNil(l.edit(dropping: "b", source: .top, destination: .onto("b"), folderName: "F"))
        XCTAssertNil(l.edit(dropping: "b", source: .top, destination: .beside("b", after: true), folderName: "F"))
        XCTAssertNil(l.edit(dropping: "b", source: .top, destination: .beside("zz", after: true), folderName: "F"))
    }

    func testVanishedIdsAreRefusedEveryWay() {
        let f = folder(["x", "y"])
        let l = LaunchpadLayout(items: [.folder(f), .app("a")], hidden: ["h"])
        let destinations: [LaunchpadDropDestination] = [.beside("a", after: true), .onto("a"), .onto(f.id.uuidString), .newPage,
                                                        .intoFolder(f.id, relativeTo: "x", after: true)]
        for d in destinations {
            XCTAssertNil(l.edit(dropping: "ghost", source: .top, destination: d, folderName: "F"), "\(d)")
            XCTAssertNil(l.edit(dropping: "h", source: .top, destination: d, folderName: "F"), "hidden \(d)")
        }
        for d in [LaunchpadDropDestination.beside("ghost", after: true), .onto("ghost"), .onto("h"), .beside("x", after: true)] {
            XCTAssertNil(l.edit(dropping: "a", source: .top, destination: d, folderName: "F"), "\(d)")
        }
        XCTAssertNil(l.edit(dropping: "a", source: .folder(f.id), destination: .newPage, folderName: "F"), "a is not in that folder")
        XCTAssertNil(l.edit(dropping: "x", source: .top, destination: .newPage, folderName: "F"), "x is not top level")
        XCTAssertNil(l.edit(dropping: "a", source: .top, destination: .intoFolder(UUID(), relativeTo: nil, after: true), folderName: "F"))
    }

    // MARK: Onto

    func testAnAppOntoAnAppMakesAFolderInTheTargetsSlotNamedByTheCaller() throws {
        let l = apps(["a", "b", "c"])
        XCTAssertEqual(l.edit(dropping: "a", source: .top, destination: .onto("c"), folderName: "Music"),
                       .makeFolder(drop: "a", onto: "c", name: "Music"))
        XCTAssertEqual(shape(dropped(l, "a", .onto("c"))), ["b", "[c,a]"])
    }

    func testAnAppOntoAFolderJoinsItLastUnlessItIsAlreadyIn() {
        let f = folder(["x", "y"])
        let l = LaunchpadLayout(items: [.folder(f), .app("a")])
        XCTAssertEqual(shape(dropped(l, "a", .onto(f.id.uuidString))), ["[x,y,a]"])
        XCTAssertNil(dropped(l, "x", from: .folder(f.id), .onto(f.id.uuidString)), "a member dropped on its own folder")
    }

    func testAFolderNeverNestsDroppedOnAnythingItOnlyTakesThePlace() {
        let f = folder(["x", "y"])
        let l = LaunchpadLayout(items: [.folder(f), .app("a"), .app("b")])
        XCTAssertEqual(shape(dropped(l, f.id.uuidString, .onto("b"))), ["a", "b", "[x,y]"])
        let g = LaunchpadLayout(items: [.app("a"), .app("b"), .folder(f)])
        XCTAssertEqual(shape(dropped(g, f.id.uuidString, .onto("a"))), ["[x,y]", "a", "b"])
        XCTAssertNil(dropped(g, f.id.uuidString, .onto(f.id.uuidString)))
        XCTAssertNil(dropped(l, f.id.uuidString, .intoFolder(f.id, relativeTo: nil, after: true)), "never into a folder")
    }

    func testAMemberDroppedOntoAnAppLeavesItsFolderAndAFolderOfTwoDissolves() {
        let f = folder(["x", "y"])
        let l = LaunchpadLayout(items: [.folder(f), .app("a")])
        XCTAssertEqual(shape(dropped(l, "x", from: .folder(f.id), .onto("a"))), ["y", "[a,x]"])
        XCTAssertEqual(shape(dropped(l, "x", from: .folder(f.id), .beside("a", after: true))), ["y", "a", "x"])
    }

    func testABlankFolderNameRefusesTheFolder() {
        let l = apps(["a", "b"])
        for blank in ["", "   ", "\n\t "] {
            XCTAssertNil(l.edit(dropping: "a", source: .top, destination: .onto("b"), folderName: blank), "\(blank.debugDescription)")
        }
    }

    // MARK: In a folder

    func testInsideAFolderAMemberMovesAndAStrangerIsAddedNextToTheAnchor() {
        let f = folder(["x", "y", "z", "w"])
        let l = LaunchpadLayout(items: [.folder(f), .app("a")])
        func inside(_ id: String, _ anchor: String?, _ after: Bool, from source: LaunchpadDropSource = .folder(f.id)) -> [String]? {
            guard case .folder(let g)? = dropped(l, id, from: source, .intoFolder(f.id, relativeTo: anchor, after: after))?.items.first else { return nil }
            return g.apps
        }
        XCTAssertEqual(inside("x", "z", false), ["y", "x", "z", "w"])
        XCTAssertEqual(inside("x", "z", true), ["y", "z", "x", "w"])
        XCTAssertEqual(inside("w", "y", false), ["x", "w", "y", "z"])
        XCTAssertEqual(inside("x", nil, true), ["y", "z", "w", "x"])
        XCTAssertEqual(inside("a", "y", true, from: .top), ["x", "y", "a", "z", "w"])
        XCTAssertEqual(inside("a", nil, true, from: .top), ["x", "y", "z", "w", "a"])
        XCTAssertNil(inside("x", "y", false), "already there")
        XCTAssertNil(inside("x", "x", true))
        XCTAssertNil(inside("x", "a", true), "an anchor that is not in the folder")
        XCTAssertNil(inside("a", "a", true, from: .top))
    }

    func testAFullFolderTakesNoMore() {
        let members = (0..<LaunchpadLimits.maxFolderApps).map { "m\($0)" }
        let f = folder(members)
        let l = LaunchpadLayout(items: [.folder(f), .app("a")])
        XCTAssertNil(l.applying(.add("a", toFolder: f.id, relativeTo: nil, after: true)))
        XCTAssertNil(l.edit(dropping: "a", source: .top, destination: .onto(f.id.uuidString), folderName: "F"))
    }

    func testTakingTheLastButOneOutOfAFolderDissolvesItAndEveryAppStaysOnce() {
        let f = folder(["x", "y", "z"])
        let l = LaunchpadLayout(items: [.app("a"), .folder(f), .app("b")])
        XCTAssertEqual(shape(dropped(l, "y", from: .folder(f.id), .beside("a", after: false))), ["y", "a", "[x,z]", "b"])
    }

    // MARK: Pages

    func testNewPagePutsTheItemLastOnAPageOfItsOwn() {
        let l = apps(["a", "b", "c"])
        XCTAssertEqual(shape(dropped(l, "a", .newPage)), ["b", "c", "|", "a"])
    }

    func testAlreadyAloneOnTheLastPageMeansNothing() {
        let l = LaunchpadLayout(items: [.app("a"), .app("b"), .pageBreak, .app("c")])
        XCTAssertNil(l.edit(dropping: "c", source: .top, destination: .newPage, folderName: "F"))
        XCTAssertEqual(shape(dropped(l, "b", .newPage)), ["a", "|", "c", "|", "b"])
    }

    func testAnEmptyPageIsDroppedWhenItsLastItemLeavesAndTheNextPageKeepsItsBreak() {
        let l = LaunchpadLayout(items: [.app("a"), .pageBreak, .app("b"), .pageBreak, .app("c"), .app("d")])
        XCTAssertEqual(shape(dropped(l, "b", .beside("a", after: true))), ["a", "b", "|", "c", "d"], "page two is gone")
        XCTAssertEqual(shape(dropped(l, "c", .beside("a", after: true))), ["a", "c", "|", "b", "|", "d"], "the page break stays where it was")
    }

    func testBreaksAtTheEdgesAndInARowAreDroppedAndAHiddenOneLeavesNoEmptyPage() throws {
        let l = LaunchpadLayout(items: [.pageBreak, .app("a"), .pageBreak, .pageBreak, .app("b"), .pageBreak])
        XCTAssertEqual(shape(l.normalized()), ["a", "|", "b"])
        let m = LaunchpadLayout(items: [.app("a"), .pageBreak, .app("b"), .pageBreak, .app("c")])
        XCTAssertEqual(shape(try XCTUnwrap(m.applying(.hide("b")))), ["a", "|", "c"])
    }

    func testABreakIsNobodysAnchorAndNobodysDragged() {
        let l = LaunchpadLayout(items: [.app("a"), .pageBreak, .app("b")])
        XCTAssertNil(l.edit(dropping: "", source: .top, destination: .beside("a", after: true), folderName: "F"))
        XCTAssertNil(l.edit(dropping: "a", source: .top, destination: .beside("", after: true), folderName: "F"))
        XCTAssertNil(l.applying(.newPage(moving: "")))
    }

    func testResetArrangementTakesTheBreaksWithTheOrder() throws {
        let l = LaunchpadLayout(items: [.app("a"), .pageBreak, .app("b")], hidden: ["h"])
        let r = try XCTUnwrap(l.applying(.resetArrangement))
        XCTAssertEqual(r.items, [])
        XCTAssertEqual(r.hidden, ["h"])
    }

    func testReconcilingKeepsABreakAndAnAppThatCameAppendsToTheLastPage() {
        let l = LaunchpadLayout(items: [.app("a"), .pageBreak, .app("b")])
        let r = l.reconciled(catalog: ["a", "b", "c"], complete: true)
        XCTAssertEqual(shape(r), ["a", "|", "b", "c"])
        XCTAssertEqual(shape(LaunchpadLayout(items: [.app("a"), .pageBreak, .app("gone")]).reconciled(catalog: ["a"], complete: true)), ["a"])
    }

    // MARK: Through the engine

    func testApplyReturnsTheSnapshotAndWritesItAndARefusedEditWritesNothing() throws {
        let dir = scratchDirectory("drop-apply")
        let store = LayoutStore(directory: dir)
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b", "c"]), launcher: FakeAppLauncher(), store: store)
        _ = engine.read()
        XCTAssertNil(engine.apply(.place("zz", relativeTo: "a", after: true)))
        XCTAssertEqual(store.load(), .absent, "a refusal writes nothing")
        let snap = try XCTUnwrap(engine.apply(.newPage(moving: "a")))
        XCTAssertTrue(snap.saved)
        XCTAssertEqual(shape(snap.layout), ["b", "c", "|", "a"])
        XCTAssertEqual(store.load(), .loaded(snap.layout))
        XCTAssertEqual(shape(engine.read().layout), ["b", "c", "|", "a"], "a read after it says the same")
    }

    // MARK: Every drop keeps every app exactly once

    func testEveryDropOverEveryPairKeepsEveryAppExactlyOnce() {
        let f = folder(["x", "y", "z"])
        let l = LaunchpadLayout(items: [.app("a"), .folder(f), .pageBreak, .app("b"), .app("c")], hidden: ["h"])
        let ids = ["a", "b", "c", "x", "y", "z", "h", "ghost", f.id.uuidString]
        let all = Set(["a", "b", "c", "x", "y", "z"])
        func flat(_ l: LaunchpadLayout) -> [String] {
            l.items.flatMap { item -> [String] in
                switch item {
                case .app(let id): [id]
                case .folder(let f): f.apps
                case .pageBreak: []
                }
            }
        }
        var destinations: [LaunchpadDropDestination] = [.newPage]
        for t in ids { destinations += [.beside(t, after: true), .beside(t, after: false), .onto(t),
                                        .intoFolder(f.id, relativeTo: t, after: true), .intoFolder(f.id, relativeTo: t, after: false)] }
        for d in ids { for source in [LaunchpadDropSource.top, .folder(f.id)] { for dest in destinations {
            guard let r = dropped(l, d, from: source, dest) else { continue }
            XCTAssertEqual(Set(flat(r)), all, "\(d) \(source) \(dest)")
            XCTAssertEqual(flat(r).count, all.count, "duplicate after \(d) \(source) \(dest)")
            XCTAssertEqual(r.hidden, ["h"])
            XCTAssertNotEqual(r.items.first, .pageBreak)
            XCTAssertNotEqual(r.items.last, .pageBreak)
        } } }
    }
}
