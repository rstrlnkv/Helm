import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The icon pipeline fed what nobody fed it: a side that is no side, a drawing that answers nothing, a render storm, a cache too small for
/// what a page asks, a folder opened over icons drawn at other sizes, a close in the middle of everything, and a first snapshot that is replaced while it waits for its icons.
/// A counting fake stands for the drawing (the port is `LaunchpadIcons.Renderer`, named at every construction but two: those test the system's own
/// drawing, the real renderer's answer).
@MainActor
final class TheLaunchpadIconPipelineUntriedInputsTests: XCTestCase {
    private final class Drawing: @unchecked Sendable {
        let asked = Locked(0)
        let finished = Locked(0)
        /// The keys asked, "pixels|path".
        let keys = Locked<Set<String>>([])
        private let gate: DispatchSemaphore?
        private let answers: Bool
        init(held: Bool = false, answers: Bool = true) { gate = held ? DispatchSemaphore(value: 0) : nil; self.answers = answers }
        func release(_ times: Int = 1) { for _ in 0..<times { gate?.signal() } }
        var renderer: LaunchpadIcons.Renderer {
            { [self] path, pixels in
                asked.withLock { $0 += 1 }
                keys.withLock { _ = $0.insert("\(pixels)|\(path)") }
                gate?.wait()
                defer { finished.withLock { $0 += 1 } }
                guard answers else { return nil }
                guard let context = CGContext(data: nil, width: min(pixels, 64), height: min(pixels, 64), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                return context.makeImage()
            }
        }
    }

    /// Holds the main thread (a plain wait, not a suspension) until `done`, then a little longer, so what the finished work posted to main is all queued.
    private nonisolated static func blockMain(until done: () -> Bool) {
        while !done() { Thread.sleep(forTimeInterval: 0.01) }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func settle(_ ms: Int = 250) async { try? await Task.sleep(for: .milliseconds(ms)) }

    // MARK: - 1. The inputs to the cache

    func testASideThatIsNoSideIsOnePixelAndNeverNoBitmap() {
        for side: CGFloat in [0, -1, -.infinity, .nan, .infinity, .leastNonzeroMagnitude, 1e300] {
            let pixels = LaunchpadIcons.pixels(side: side, scale: 2)
            XCTAssertTrue((1...4096).contains(pixels), "side \(side) gave \(pixels) pixels")
        }
        XCTAssertTrue((1...4096).contains(LaunchpadIcons.pixels(side: 32, scale: .nan)))
        XCTAssertTrue((1...4096).contains(LaunchpadIcons.pixels(side: 32, scale: 0)))
    }

    func testTheSystemsDrawingIsNeverAskedForABitmapItCannotMake() async {
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2)
        for side: CGFloat in [0, -5, .nan, .infinity, 1e9] {
            _ = icons.image(for: "/System/Library/CoreServices/Finder.app", side: side)
        }
        await settle()
        XCTAssertGreaterThan(icons.rendered, 0, "no side produced a bitmap")
        XCTAssertNil(LaunchpadIconRender.render(path: "/x", pixels: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!))
        XCTAssertNil(LaunchpadIconRender.render(path: "/x", pixels: -3, space: CGColorSpace(name: CGColorSpace.sRGB)!))
        XCTAssertNil(LaunchpadIconRender.render(path: "/x", pixels: 4097, space: CGColorSpace(name: CGColorSpace.sRGB)!))
    }

    func testAPathThatNoLongerExistsStillGetsAnImageFromTheSystem() async {
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2)
        await waitUntil("the icon of a gone app landed") { icons.image(for: "/Applications/GoneSinceYesterday-\(UUID()).app", side: 32) != nil
            || icons.rendered > 0 }
        XCTAssertGreaterThan(icons.rendered, 0, "a path that is gone drew nothing, so its tile stays empty")
    }

    /// A drawing that answers nothing must not be asked again on every body pass: nothing says to draw again, and each pass would start another.
    func testADrawingThatAnswersNothingIsNotAskedAgainOnEveryPass() async {
        let drawing = Drawing(answers: false)
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2, render: drawing.renderer)
        let warmed = await icons.warm([("/Applications/a.app", 32)], deadline: .seconds(5))
        XCTAssertEqual(warmed.drawn, 0)
        XCTAssertFalse(warmed.timedOut, "a failed drawing settled its key; no deadline was reached")
        for _ in 0..<10 {
            _ = icons.image(for: "/Applications/a.app", side: 32)
            await waitUntil("the drawing answered") { drawing.finished.value == drawing.asked.value }
            await settle(30)
        }
        XCTAssertLessThanOrEqual(drawing.asked.value, 2, "a path that cannot be drawn was drawn \(drawing.asked.value) times in ten passes: a render storm")
    }

    func testTheSamePathAtTwoSidesDuringAReconfigureHoldIsDrawnOncePerSideAndOnlyAfterTheHold() async {
        let drawing = Drawing(held: true)
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2, render: drawing.renderer)
        icons.reconfigure(capacity: 4, side: 80, scale: 2)
        _ = icons.image(for: "/Applications/a.app", side: 32)
        _ = icons.image(for: "/Applications/a.app", side: 48)
        _ = icons.image(for: "/Applications/a.app", side: 48)
        await settle(30)
        XCTAssertEqual(drawing.asked.value, 0, "the hold drew before its 80 ms")
        await waitUntil("both sides drawn after the hold") { drawing.release(); return drawing.asked.value == 2 }
        drawing.release(2)
        await waitUntil("both landed") { icons.rendered == 2 }
        await settle(100)
        XCTAssertEqual(drawing.asked.value, 2)
    }

    func testRemoveAllBetweenWarmAndItsDeadlineEndsTheWarmAtOnceWithNothingDrawn() async {
        let drawing = Drawing(held: true)
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2, render: drawing.renderer)
        let started = ContinuousClock.now
        let task = Task { await icons.warm([("/Applications/a.app", 32), ("/Applications/b.app", 32)], deadline: .seconds(5)) }
        await waitUntil("the drawing is under way") { drawing.asked.value >= 1 }
        icons.removeAll()
        let result = await task.value
        drawing.release(2)
        XCTAssertEqual(result.drawn, 0)
        XCTAssertLessThan(started.duration(to: .now), .seconds(2), "the warm waited its deadline though the window had closed")
        await settle()
        XCTAssertEqual(icons.rendered, 0)
    }

    func testAWarmOfNothingAndAWarmWithNoTimeAnswerAtOnce() async {
        let drawing = Drawing(held: true)
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2, render: drawing.renderer)
        let none = await icons.warm([], deadline: .seconds(5))
        XCTAssertEqual(none.drawn, 0)
        XCTAssertEqual(none.wanted, 0)
        let late = await icons.warm([("/Applications/a.app", 32)], deadline: .zero)
        XCTAssertEqual(late.drawn, 0)
        XCTAssertEqual(late.wanted, 1)
        drawing.release()
        icons.removeAll()
    }

    /// A page of nine-app folders, as the screen asks it: each tile's folder mark asks nine minis, so a page of `capacity` folders asks
    /// 9 x capacity distinct (path, side) keys. The bound is sized for three such pages (`LaunchpadIcons.limits`); the second half asks
    /// more than any bound and must still settle, because an arrival may not evict what the redraw it follows asked.
    func testAPageOfFullFoldersSettlesAndStopsDrawing() async {
        let drawing = Drawing()
        let capacity = 35
        let icons = LaunchpadIcons(capacity: capacity, side: 80, scale: 2, render: drawing.renderer)
        let paths = (0..<capacity * 9).map { "/Applications/app\($0).app" }
        let ask = { for path in paths { _ = icons.image(for: path, side: 16) } }
        icons.onArrival = ask
        ask()
        await settle(800)
        let after = drawing.asked.value
        await settle(800)
        XCTAssertEqual(drawing.asked.value, after, "a page of full folders keeps drawing icons it drew before: eviction and redraw chase each other (\(after) drawings for \(paths.count) icons)")
        XCTAssertEqual(after, paths.count, "each icon is drawn once")
    }

    func testAskingMoreThanTheBoundHoldsStillEndsInTheLoop() async {
        let drawing = Drawing()
        let capacity = 4
        let icons = LaunchpadIcons(capacity: capacity, side: 80, scale: 2, render: drawing.renderer)
        let paths = (0..<capacity * 50).map { "/Applications/app\($0).app" }
        let ask = { for path in paths { _ = icons.image(for: path, side: 16) } }
        icons.onArrival = ask
        ask()
        await settle(800)
        let after = drawing.asked.value
        await settle(500)
        XCTAssertEqual(drawing.asked.value, after, "twice the bound asked by one redraw never settles")
        XCTAssertEqual(after, paths.count)
    }

    func testTheBoundIsWhatThreePagesAndAnOpenCardCanAsk() {
        let limits = LaunchpadIcons.limits(capacity: 40, side: 80, scale: 2)
        XCTAssertEqual(limits.count, 1200)
        XCTAssertEqual(limits.cost, 24_576_000)
    }

    /// A folder opens over apps that were drawn as its mini: the card's tile, at the grid's side, shows that image scaled until its own lands.
    func testAnAppDrawnAtOneSideIsShownScaledAtAnyOtherUntilItsOwnLands() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2, render: drawing.renderer)
        XCTAssertNil(icons.image(for: "/Applications/a.app", side: 16))
        await waitUntil("the mini landed") { icons.rendered == 1 }
        XCTAssertNotNil(icons.image(for: "/Applications/a.app", side: 80), "the card's tile is an empty slot while the mini is on the page")
        await waitUntil("the card's own landed") { icons.rendered == 2 }
        let own = icons.image(for: "/Applications/a.app", side: 80)
        _ = icons.image(for: "/Applications/a.app", side: 16)
        XCTAssertTrue(own === icons.image(for: "/Applications/a.app", side: 80), "the exact image is the hit")
        XCTAssertEqual(icons.rendered, 2)
    }

    // MARK: - 3. Delivery

    func testArrivalsThatLandInOneTurnAreOneRedrawAndNoneAfterRemoveAll() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 40, side: 80, scale: 2, render: drawing.renderer)
        let arrivals = Locked(0)
        icons.onArrival = { arrivals.withLock { $0 += 1 } }
        for i in 0..<20 { _ = icons.image(for: "/Applications/app\(i).app", side: 32) }
        // Main is busy while they all finish, so every landing is queued behind this turn.
        Self.blockMain(until: { drawing.finished.value >= 20 })
        await waitUntil("all landed") { icons.rendered == 20 }
        await settle(100)
        XCTAssertEqual(arrivals.value, 1, "twenty landings in one turn said \(arrivals.value) times to draw again")
        // A landing whose redraw is queued (its landing has run, the say is behind it) when the window closes says nothing.
        _ = icons.image(for: "/Applications/late.app", side: 32)
        Self.blockMain(until: { drawing.finished.value >= 21 })
        let closed = expectation(description: "closed between the landing and its say")
        DispatchQueue.main.async { MainActor.assumeIsolated { icons.removeAll(); closed.fulfill() } }
        await fulfillment(of: [closed], timeout: 5)
        await settle(100)
        XCTAssertEqual(icons.rendered, 21, "the landing did not run first, so the test did not reach what it is about")
        XCTAssertEqual(arrivals.value, 1, "a redraw queued before the close was said after it")
    }

    func testNeitherTheCacheNorAnOperationInFlightKeepsItsOwnerAlive() async {
        let drawing = Drawing(held: true)
        weak var weakIcons: LaunchpadIcons?
        do {
            let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2, render: drawing.renderer)
            weakIcons = icons
            _ = icons.image(for: "/Applications/a.app", side: 32)
            _ = icons.image(for: "/Applications/b.app", side: 32)
            icons.reconfigure(capacity: 4, side: 80, scale: 3)
            _ = icons.image(for: "/Applications/c.app", side: 32)
        }
        await settle(200)
        XCTAssertNil(weakIcons, "the queue, a held ask or a hold task kept the cache alive")
        drawing.release(3)
    }

    // MARK: - 2. The gate

    private func gated(_ rig: LiftRig, _ drawing: Drawing) -> (LaunchpadScreenState, LaunchpadIcons) {
        let icons = LaunchpadIcons(capacity: rig.g.capacity, side: 80, scale: 2, render: drawing.renderer)
        return (LaunchpadScreenState(geometry: rig.g, icons: icons), icons)
    }

    /// Page 0 as the screen cuts it: a page break ends it, an app the snapshot does not hold takes no cell, a folder's apps are asked at its mini.
    func testTheGateWarmsExactlyWhatPageZeroDrawsAtTheSidesItDrawsThem() async {
        let layout = LaunchpadLayout(items: [.app("ghost"), .app("a"), .folder(.init(id: UUID(), name: "F", apps: ["b", "c"])), .pageBreak, .app("d"), .app("e")])
        let rig = LiftRig(self, apps: ["a", "b", "c", "d", "e"], layout: layout)
        let drawing = Drawing()
        let (state, _) = gated(rig, drawing)
        state.update(snapshot: rig.engine.read(reason: .refresh))
        await waitUntil("the snapshot landed") { state.mode == .grid }
        let tile = LaunchpadIcons.pixels(side: rig.g.icon, scale: 2), mini = LaunchpadIcons.pixels(side: LaunchpadFolderMark.mini(rig.g.icon), scale: 2)
        XCTAssertEqual(drawing.keys.value, ["\(tile)|/Applications/a.app", "\(mini)|/Applications/b.app", "\(mini)|/Applications/c.app"])
    }

    func testASnapshotThatArrivesWhileTheGateWaitsReplacesItAndLoadsOnce() async {
        let rig = LiftRig(self, apps: ["a", "b"])
        let drawing = Drawing(held: true)
        let (state, _) = gated(rig, drawing)
        let loaded = Locked<[Int]>([])
        state.onLoaded = { snapshot, _ in loaded.withLock { $0.append(snapshot.apps.count) } }
        state.update(snapshot: rig.engine.read(reason: .refresh))
        rig.catalog.reading = CatalogReading(apps: ["a", "b", "c", "d"].map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }, complete: true)
        state.update(snapshot: rig.engine.read(reason: .refresh))
        await waitUntil("the snapshot landed") { state.mode == .grid }
        drawing.release(8)
        await settle(300)
        XCTAssertEqual(loaded.value, [4], "the gate loaded \(loaded.value): the older snapshot, or twice, or never")
        XCTAssertEqual(state.pageCount, 1)
    }

    func testANilSnapshotWhileTheGateWaitsDropsTheFirstAndTheNextOneStillLoadsOnce() async {
        let rig = LiftRig(self, apps: ["a"])
        let drawing = Drawing(held: true)
        let (state, _) = gated(rig, drawing)
        let loaded = Locked(0)
        state.onLoaded = { _, _ in loaded.withLock { $0 += 1 } }
        state.update(snapshot: rig.engine.read(reason: .refresh))
        state.update(snapshot: nil)
        state.update(snapshot: rig.engine.read(reason: .refresh))
        await waitUntil("the snapshot landed") { state.mode == .grid }
        drawing.release(4)
        await settle(300)
        XCTAssertEqual(loaded.value, 1)
    }

    func testClosingDuringTheGateLoadsNothingAndLeavesNothingHoldingTheState() async {
        let rig = LiftRig(self, apps: ["a", "b"])
        let drawing = Drawing(held: true)
        let loaded = Locked(0)
        weak var weakState: LaunchpadScreenState?
        weak var weakIcons: LaunchpadIcons?
        await { () async in
            let (state, icons) = gated(rig, drawing)
            weakState = state
            weakIcons = icons
            state.onLoaded = { _, _ in loaded.withLock { $0 += 1 } }
            state.update(snapshot: rig.engine.read(reason: .refresh))
            // The gate's task is under way, waiting on an icon that is held, when the window closes.
            await waitUntil("the drawing is under way") { drawing.asked.value >= 1 }
            state.shutdown()
            icons.removeAll()
        }()
        drawing.release(4)
        await settle(500)
        XCTAssertEqual(loaded.value, 0, "a window that closed during the gate loaded its snapshot")
        XCTAssertNil(weakState, "the gate's task held the state after the window closed")
        XCTAssertNil(weakIcons, "the cache outlived the state")
    }

    func testTheGateFiresOnLoadedOnceWhenTheDeadlineAndTheLastIconMeet() async {
        let rig = LiftRig(self, apps: ["a"])
        let drawing = Drawing()
        let (state, _) = gated(rig, drawing)
        let loaded = Locked(0)
        state.onLoaded = { _, _ in loaded.withLock { $0 += 1 } }
        state.update(snapshot: rig.engine.read(reason: .refresh))
        await waitUntil("the snapshot landed") { state.mode == .grid }
        await settle(400)
        XCTAssertEqual(loaded.value, 1)
    }
}
