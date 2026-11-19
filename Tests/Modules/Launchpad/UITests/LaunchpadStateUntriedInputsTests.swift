import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// What nobody fed the window's state: the catalog changing between a press and its release, a second press while a drop is
/// still being written, a window that closes with a timer armed, a folder that goes while a tile is carried, names typed oddly.
@MainActor final class LaunchpadStateUntriedInputsTests: XCTestCase {
    private let six = ["a", "b", "c", "d", "e", "f"]
    private let folderID = UUID()
    private func rig(_ layout: LaunchpadLayout? = nil) -> LiftRig { LiftRig(self, apps: six, layout: layout) }
    private func catalog(_ ids: [String], _ r: LiftRig) {
        r.catalog.reading = CatalogReading(apps: ids.map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }, complete: true)
        r.state.update(snapshot: r.engine.read())
    }

    /// A write that waits until the test lets it through.
    @MainActor private final class Gate {
        var waiting: CheckedContinuation<Void, Never>?
        var open = false
        var landed = 0
        func pass() async {
            if open { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func release() { open = true; waiting?.resume(); waiting = nil }
    }

    // MARK: A press and what the catalog does before its release

    func testAPressIsOnTheAppItWasOnWhateverTheSnapshotMovedUnderIt() {
        let r = rig()
        XCTAssertTrue(r.state.pointerDown(r.core(2), time: 0))
        XCTAssertEqual(r.state.pressedID, "c")
        catalog(Array(six.dropFirst()), r)
        XCTAssertEqual(r.ids(), ["b", "c", "d", "e", "f"], "the control: the tile under the pointer is now another")
        r.state.pointerUp(r.core(2), time: 0.1)
        XCTAssertEqual(r.launched.filter { $0 != "c" }, [], "the app pressed was c; what is now under the pointer was never pressed: \(r.launched)")
    }

    func testAPressOnAnAppThatIsUninstalledBeforeItsReleaseLaunchesNothing() {
        let r = rig()
        XCTAssertTrue(r.state.pointerDown(r.core(2), time: 0))
        catalog(six.filter { $0 != "c" }, r)
        r.state.pointerUp(r.core(2), time: 0.1)
        XCTAssertEqual(r.launched, [], "c is gone: nothing else takes the click")
    }

    func testAPressThatBecomesALiftCarriesTheAppItWasOn() {
        let r = rig()
        XCTAssertTrue(r.state.pointerDown(r.core(2), time: 0))
        catalog(Array(six.dropFirst()), r)
        r.state.pointerMoved(CGPoint(x: r.core(2).x + 20, y: r.core(2).y), time: 0.1)
        if let carried = r.state.lift?.entry.id { XCTAssertEqual(carried, "c", "carried \(carried)") }
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testAClickOnAFolderTileOpensThatFolderAndAClickAfterAMovedSnapshotOpensNone() {
        let r = withFolder()
        XCTAssertTrue(r.state.pointerDown(r.core(1), time: 0))
        r.state.pointerUp(r.core(1), time: 0.1)
        XCTAssertEqual(r.state.openFolder, folderID, "a press on the folder tile is a click on it, by its address")
        XCTAssertEqual(r.launched, [])
        r.state.closeFolder()
        XCTAssertNil(r.state.openFolder)
        XCTAssertTrue(r.state.pointerDown(r.core(1), time: 1))
        catalog(["a", "d", "e", "f"], r)   // the folder's apps go: the folder tile is gone from slot 1
        r.state.pointerUp(r.core(1), time: 1.1)
        XCTAssertNil(r.state.openFolder, "the tile now at slot 1 was not the one pressed")
        XCTAssertEqual(r.launched, [])
    }

    // MARK: A second press while a drop is being written

    func testAPressWhileTheLastDropIsStillBeingWrittenLiftsFromTheTilesAsTheyAreShown() async {
        let r = rig()
        let gate = Gate()
        r.state.onPlace = { [unowned r] edit in
            await gate.pass()
            defer { gate.landed += 1 }
            return r.engine.apply(edit)
        }
        r.lift(0)
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.tick(at: 1.2)
        r.state.pointerUp(r.margin(3), time: 1.3)
        XCTAssertEqual(r.ids(), ["b", "c", "d", "a", "e", "f"], "the drop is shown at once")
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 2), "the press is taken: nothing says a write is out")
        r.state.pointerMoved(CGPoint(x: r.core(0).x + 20, y: r.core(0).y), time: 2.1)
        XCTAssertEqual(r.state.lift?.entry.id, "b")
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, "c", "d", "a", "e", "f"], "the first drop does not un-happen under the second lift")
        gate.release()
        await waitUntil("the first drop landed") { gate.landed == 1 }
        await waitUntil("the answer is in") { r.state.pages[0].contains(.gap) }
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, "c", "d", "a", "e", "f"], "and after the answer the same")
        XCTAssertEqual(r.state.lift?.entry.id, "b")
    }

    func testAFolderLetGoOntoAnAppIsNeverMissingFromThePageWhileTheDropIsBeingWritten() async {
        let r = withFolder()
        let gate = Gate()
        r.state.onPlace = { [unowned r] edit in
            await gate.pass()
            defer { gate.landed += 1 }
            return r.engine.apply(edit)
        }
        r.lift(1)
        r.state.pointerMoved(r.core(2), time: 1)
        r.state.tick(at: 1.31)
        XCTAssertEqual(r.state.lift?.onto, "d", "the control: it is armed on d")
        r.state.pointerUp(r.core(2), time: 1.4)
        XCTAssertNil(r.state.lift, "the control: it was let go")
        XCTAssertTrue(r.ids().contains(folderID.uuidString), "a folder only reorders: it is somewhere on the page while its write is out: \(r.ids())")
        gate.release()
        await waitUntil("the write landed") { gate.landed == 1 }
        XCTAssertTrue(r.ids().contains(folderID.uuidString))
    }

    // MARK: Close with a timer armed

    func testAWindowThatClosesWithATimerArmedGetsNoTickAfterIt() async {
        func armed(shutdown: Bool) async -> Int {
            let r = rig()
            var asked = 0
            r.state.buttonDown = { asked += 1; return true }
            r.lift(0, at: ProcessInfo.processInfo.systemUptime)
            r.state.pointerMoved(r.margin(3), time: ProcessInfo.processInfo.systemUptime)
            if shutdown { r.state.shutdown() }
            try? await Task.sleep(for: .milliseconds(400))
            return asked
        }
        let live = await armed(shutdown: false)
        XCTAssertGreaterThan(live, 0, "the control: the armed timer does tick")
        let closed = await armed(shutdown: true)
        XCTAssertEqual(closed, 0, "no tick after the window closed")
    }

    func testAMouseEventAfterTheCloseDoesNothingAndAShutdownTwiceIsTheSameAsOnce() {
        let r = rig()
        r.lift(0)
        r.state.shutdown()
        r.state.shutdown()
        r.state.pointerMoved(r.margin(3), time: 5)
        r.state.pointerUp(r.margin(3), time: 5.1)
        r.state.tick(at: 9)
        XCTAssertNil(r.state.lift)
        XCTAssertTrue(r.placed.isEmpty)
        XCTAssertEqual(r.ids(), six)
    }

    // MARK: A folder or an app that goes while a tile is carried

    private func withFolder() -> LiftRig {
        rig(LaunchpadLayout(items: [.app("a"), .folder(.init(id: folderID, name: "F", apps: ["b", "c"])), .app("d"), .app("e"), .app("f")]))
    }

    func testTheCarriedTilesFolderDissolvedByASnapshotCancelsTheLiftAndKeepsTheCardClosed() {
        let r = withFolder()
        r.state.open(folder: folderID)
        let card = LaunchpadSurface.Card(geometry: r.g, count: 2)
        let from = card.center(ofSlot: 0)
        XCTAssertTrue(r.state.pointerDown(from, time: 0))
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.1)
        XCTAssertEqual(r.state.lift?.entry.id, "b", "the control: the app in the card is carried")
        catalog(["a", "b", "d", "e", "f"], r)
        XCTAssertNil(r.state.lift, "c went: the folder of one is its app, and the card with it")
        XCTAssertNil(r.state.openFolder)
        XCTAssertFalse(r.state.pointerBusy)
        r.state.pointerUp(from, time: 1)
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testTheOpenFolderGoingWhileATopTileIsCarriedLetsTheLiftGoOnOverTheGrid() {
        let r = withFolder()
        r.lift(0)
        r.state.pointerMoved(r.core(1), time: 1)
        r.state.tick(at: 1.31)
        r.state.tick(at: 1.71)
        XCTAssertEqual(r.state.openFolder, folderID, "the control: held on the folder it opened")
        catalog(["a", "d", "e", "f"], r)
        XCTAssertNil(r.state.openFolder)
        XCTAssertEqual(r.state.lift?.entry.id, "a", "a was never in the folder")
        XCTAssertEqual(r.state.cardEntries, [])
        XCTAssertEqual(r.state.pages[0].filter { $0 == .gap }.count, 1, "one gap")
        r.state.pointerUp(r.margin(2), time: 3)
        XCTAssertLessThanOrEqual(r.placed.count, 1)
    }

    // MARK: Names

    func testADraftThatIsTheOldNameWithSpacesAroundItWritesNothingAndAWhitespaceOnlyOneEither() {
        let r = withFolder()
        r.state.open(folder: folderID)
        r.state.beginRenaming(selectAll: false)
        r.state.nameDraft = "  F \n"
        r.state.commitName()
        r.state.beginRenaming(selectAll: false)
        r.state.nameDraft = " \t \n"
        r.state.commitName()
        XCTAssertEqual(r.renamed, [])
        XCTAssertEqual(r.state.nameDraft, "F")
        XCTAssertFalse(r.state.renaming)
    }

    func testAVeryLongNameIsWrittenAndTheCardHoldsNoMoreThanTheEngineKeeps() async {
        let r = withFolder()
        r.state.open(folder: folderID)
        r.state.beginRenaming(selectAll: false)
        r.state.nameDraft = String(repeating: "x", count: 100_000)
        r.state.commitName()
        await waitUntil("the name was written") { r.renamed.count == 1 }
        await waitUntil("the snapshot answered") { r.state.folderName.count < 100_000 }
        XCTAssertLessThanOrEqual(r.state.folderName.count, 64)
        XCTAssertLessThanOrEqual(r.state.nameDraft.count, 64)
    }
}
