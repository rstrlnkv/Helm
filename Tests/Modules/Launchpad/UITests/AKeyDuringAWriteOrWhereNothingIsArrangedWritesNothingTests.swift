import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A reorder by key needs an arrangement and nobody else writing one: with search text, in the category view, in a Hidden or a
/// category card, while a name is typed, with a press on a tile, and while an earlier write is out, the chord writes nothing and,
/// but for the last two (the panel swallows every key during a press, and the write's answer lands within a moment), is not the
/// state's, so the field keeps its Option+arrow.
@MainActor final class AKeyDuringAWriteOrWhereNothingIsArrangedWritesNothingTests: XCTestCase {
    private let apps = ["a", "b", "c", "d", "e", "f", "g"]

    private func rig() -> LiftRig {
        let r = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: apps.map { .app($0) }))
        r.categorize(Dictionary(uniqueKeysWithValues: apps.map { ($0, "public.app-category.music") }))
        return r
    }

    private func armed(_ r: LiftRig) {
        r.choose("c")
        XCTAssertTrue(r.state.reorderAllowed, "subject: the same state allows a reorder before the condition")
    }

    private func assertRefused(_ r: LiftRig, _ why: String, bytes: Data?, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertFalse(r.state.reorderAllowed, why, file: file, line: line)
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: false), "\(why): the key is not the state's", file: file, line: line)
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: true), why, file: file, line: line)
        XCTAssertNil(r.state.moves(for: "c"), "\(why): VoiceOver is offered nothing", file: file, line: line)
        r.state.reorder(tile: "c", .move(dx: 1, dy: 0))
        await grace()
        XCTAssertTrue(r.placed.isEmpty, "\(why): nothing was written", file: file, line: line)
        XCTAssertEqual(try? Data(contentsOf: r.layoutFile), bytes, "\(why): the file is the same bytes", file: file, line: line)
    }

    func testNothingIsWrittenAndNoKeyIsTakenWhereNothingIsArranged() async {
        var r = rig()
        var bytes = try? Data(contentsOf: r.layoutFile)

        armed(r)
        r.state.search = "c"
        await assertRefused(r, "search text", bytes: bytes)

        r = rig(); bytes = try? Data(contentsOf: r.layoutFile)
        armed(r)
        r.state.setView(.categories)
        await assertRefused(r, "the category view", bytes: bytes)

        r = rig(); bytes = try? Data(contentsOf: r.layoutFile)
        r.state.setView(.categories)
        r.state.open(folder: UUID(uuidString: r.state.pages[0][0].id)!)
        XCTAssertNotNil(r.state.openFolder, "subject: a category block's card is open")
        r.state.move(dx: 1, dy: 0)
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: false), "a category card")
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: true), "a category card, Shift")
        await grace()
        XCTAssertTrue(r.placed.isEmpty)
        XCTAssertEqual(try? Data(contentsOf: r.layoutFile), bytes)

        let f = UUID()
        r = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: [.folder(.init(id: f, name: "F", apps: ["a", "b", "c"])), .app("d")]))
        bytes = try? Data(contentsOf: r.layoutFile)
        r.state.open(folder: f)
        r.state.move(dx: 1, dy: 0)
        XCTAssertTrue(r.state.reorderAllowed, "subject: a folder's card allows a reorder")
        r.state.beginRenaming(selectAll: false)
        XCTAssertTrue(r.state.renaming)
        XCTAssertFalse(r.state.reorderAllowed, "a name being typed")
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: false), "the caret's Option+arrow stays the field's")
        await grace()
        XCTAssertTrue(r.placed.isEmpty)
        XCTAssertEqual(try? Data(contentsOf: r.layoutFile), bytes)
    }

    func testAPressOnATileIsNotAReorder() async {
        let r = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: apps.map { .app($0) }))
        let bytes = try? Data(contentsOf: r.layoutFile)
        r.choose("c")
        XCTAssertTrue(r.state.reorderAllowed, "subject")
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        XCTAssertTrue(r.state.pointerBusy)
        XCTAssertFalse(r.state.reorderAllowed)
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: false))
        r.state.reorder(tile: "c", .move(dx: 1, dy: 0))
        await grace()
        XCTAssertTrue(r.placed.isEmpty)
        XCTAssertEqual(try? Data(contentsOf: r.layoutFile), bytes)
    }

    /// A write that waits for its answer.
    @MainActor private final class Slow {
        var waiting: CheckedContinuation<Void, Never>?
        var edits: [LaunchpadEdit] = []
        func wait() async { await withCheckedContinuation { waiting = $0 } }
        func release() { waiting?.resume(); waiting = nil }
    }

    func testAKeyDuringAWriteIsDroppedNotQueued() async {
        let r = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: apps.map { .app($0) }))
        let slow = Slow()
        r.state.onPlace = { [unowned r] edit in
            slow.edits.append(edit)
            await slow.wait()
            return r.engine.apply(edit)
        }
        r.choose("c")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(slow.edits.count, 1, "subject: the first write is out and waiting")
        XCTAssertFalse(r.state.reorderKey(dx: 1, dy: 0, combine: false), "a key during the write is not the state's")
        r.state.reorder(tile: "c", .move(dx: 1, dy: 0))
        await grace()
        XCTAssertEqual(slow.edits.count, 1, "and writes nothing: not now, not queued")
        slow.release()
        await grace()
        XCTAssertEqual(slow.edits.count, 1, "nor after the answer")
        XCTAssertEqual(r.ids(0).prefix(4), ["a", "b", "d", "c"], "the first write landed once")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: false), "the next key, after the answer, is taken")
    }
}
