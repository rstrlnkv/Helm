import HelmUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A folder's card has pages, and a lifted app is carried through them with a gap. The gap is an index into the folder's whole
/// list, so a page that turns under the lift must take the gap with it, or the release writes the person's order to the page
/// they are not looking at. Sizes come from `Card.capacity`, never a literal: the window's grid decides how big a page is.
@MainActor final class AReleaseInAPagedCardLandsOnTheShownPageTests: XCTestCase {
    private let folderID = UUID()

    private var capacity: Int {
        LaunchpadSurface.Card(geometry: .make(for: CGSize(width: 1280, height: 800), topSafe: 0), count: 10_000).capacity
    }

    private func names(_ count: Int) -> [String] { (0..<count).map { "f\($0)" } }

    /// x, a folder of `count` apps, y.
    private func rig(folderApps count: Int) -> LiftRig {
        LiftRig(self, apps: ["x", "y"] + names(count),
                layout: LaunchpadLayout(items: [.app("x"), .folder(.init(id: folderID, name: "F", apps: names(count))), .app("y")]))
    }

    private func card(_ r: LiftRig, page: Int = 0) -> LaunchpadSurface.Card {
        LaunchpadSurface.Card(geometry: r.g, count: r.state.cardEntries.count, page: page)
    }

    /// `x` lifted and held on the folder until its card opens.
    private func openedByALift(_ r: LiftRig) {
        r.lift(0)
        r.state.pointerMoved(r.core(1), time: 1)
        r.state.tick(at: 1.31)
        XCTAssertEqual(r.state.lift?.onto, folderID.uuidString, "the control: armed before it opens")
        r.state.tick(at: 1.71)
        XCTAssertEqual(r.state.openFolder, folderID, "the control: it opened")
    }

    /// The pointer in the card's left strip: in its padding (`inMargin` false) or outside it, in the margin around it.
    private func strip(_ r: LiftRig, inMargin: Bool) -> CGPoint {
        let c = card(r)
        let x = inMargin ? c.rect.minX - LaunchpadLiftTiming.cardMargin / 2 : c.origin.x - c.geometry.cardPadding / 2
        return CGPoint(x: x, y: c.rect.midY)
    }

    private func gapIndex(_ r: LiftRig) -> Int? { r.state.cardEntries.firstIndex(of: .gap) }

    /// Holds the pointer on a card strip until the page turns; returns the time it did.
    private func turned(_ r: LiftRig, at point: CGPoint, from time: TimeInterval) -> TimeInterval {
        r.state.pointerMoved(point, time: time)
        r.state.tick(at: time + LaunchpadLiftTiming.edgeFirst + 0.01)
        return time + LaunchpadLiftTiming.edgeFirst + 0.01
    }

    // MARK: (a) it opens on the last page, the gap at the end

    func testAFolderOpenedByALiftShowsItsLastPageWithTheGapAtTheEnd() {
        let cap = capacity
        XCTAssertGreaterThan(cap, 2, "the control: a page holds more than a couple of tiles, or the sizes below mean nothing")
        // Exactly a page of apps (the gap makes a second page), a page and one, two pages and a bit: the same answer.
        for count in [cap - 1, cap, cap + 1, 2 * cap, 2 * cap + 3] {
            let r = rig(folderApps: count)
            openedByALift(r)
            let c = card(r)
            XCTAssertEqual(r.state.cardEntries.count, count + 1, "\(count): the apps and the gap")
            XCTAssertEqual(gapIndex(r), count, "\(count): the gap is at the end")
            XCTAssertEqual(r.state.cardPage, c.pageCount - 1, "\(count): the last page is shown")
            XCTAssertEqual(c.pageCount, (count + 1 + cap - 1) / cap, "\(count): the control: pages from the capacity")
            XCTAssertTrue(c.range(ofPage: r.state.cardPage).contains(count), "\(count): the gap is on the shown page")
        }
    }

    // MARK: (b) a turn under the pointer, then a release

    func testAReleaseInTheLeftStripAfterATurnWritesTheAnchorOnTheShownPage() async {
        for inMargin in [false, true] {
            let cap = capacity
            let r = rig(folderApps: cap + 3)
            openedByALift(r)
            let last = r.state.cardPage
            XCTAssertEqual(last, 1, "the control: two pages")
            let point = strip(r, inMargin: inMargin)
            XCTAssertEqual(LaunchpadHit.at(point, in: LaunchpadSurface(geometry: r.g, page: 0, pageCounts: [3], gap: nil, card: card(r, page: last))),
                           .edge(-1), "the control: the point is on the card's left strip (inMargin \(inMargin))")
            let time = turned(r, at: point, from: 2)
            XCTAssertEqual(r.state.cardPage, 0, "inMargin \(inMargin): the page turned (asserted first)")
            XCTAssertEqual(gapIndex(r), cap - 1, "inMargin \(inMargin): the gap came with it, to the last place of the page shown")
            XCTAssertEqual(r.state.openFolder, folderID)
            r.state.pointerUp(point, time: time + 0.1)
            await waitUntil("the app joined") { r.state.folderApps.count == cap + 4 }
            XCTAssertEqual(r.placed, [.add("x", toFolder: folderID, relativeTo: "f\(cap - 2)", after: true)], "inMargin \(inMargin): the anchor is on page 0")
            XCTAssertEqual(r.state.folderApps.firstIndex { $0.id == "x" }, cap - 1, "inMargin \(inMargin): it landed where the person saw the gap")
            XCTAssertEqual(r.state.openFolder, folderID, "inMargin \(inMargin): a release on the strip is a release in the card")
        }
    }

    func testTurnsBackAndForthSeatTheGapOnEachShownPage() async {
        let cap = capacity
        let r = rig(folderApps: 2 * cap + 3)
        openedByALift(r)
        XCTAssertEqual(r.state.cardPage, 2)
        let left = strip(r, inMargin: false)
        var time = turned(r, at: left, from: 2)
        XCTAssertEqual(r.state.cardPage, 1)
        XCTAssertEqual(gapIndex(r), 2 * cap - 1, "backward: the end of the page now shown")
        time = turned(r, at: CGPoint(x: left.x, y: left.y + 1), from: time + 1)
        XCTAssertEqual(r.state.cardPage, 0)
        XCTAssertEqual(gapIndex(r), cap - 1)
        let c = card(r)
        let right = CGPoint(x: c.origin.x + c.pageWidth + c.geometry.cardPadding / 2, y: c.rect.midY)
        time = turned(r, at: right, from: time + 1)
        XCTAssertEqual(r.state.cardPage, 1)
        XCTAssertEqual(gapIndex(r), cap, "forward: the first place of the page now shown")
        r.state.pointerUp(right, time: time + 0.1)
        await waitUntil("the app joined") { r.state.folderApps.count == 2 * cap + 4 }
        XCTAssertEqual(r.placed, [.add("x", toFolder: folderID, relativeTo: "f\(cap - 1)", after: true)])
        XCTAssertEqual(r.state.folderApps.firstIndex { $0.id == "x" }, cap)
    }

    func testTheLastPagesRightStripTurnsNothingAndMakesNoPage() {
        let cap = capacity
        let r = rig(folderApps: cap + 3)
        openedByALift(r)
        let c = card(r)
        let right = CGPoint(x: c.origin.x + c.pageWidth + c.geometry.cardPadding / 2, y: c.rect.midY)
        let pages = r.state.pages.count
        r.state.pointerMoved(right, time: 2)
        r.state.tick(at: 2.61)
        r.state.tick(at: 3.6)
        XCTAssertEqual(r.state.cardPage, 1)
        XCTAssertEqual(r.state.pages.count, pages, "no grid page was made behind the card")
        XCTAssertEqual(gapIndex(r), cap + 3)
    }

    // MARK: (c) a snapshot lands mid-lift while the card shows another page

    func testASnapshotLandingMidLiftOnAnotherPageStillReleasesOnTheShownPage() async {
        let cap = capacity
        let r = rig(folderApps: cap + 3)
        openedByALift(r)
        let point = strip(r, inMargin: true)
        let time = turned(r, at: point, from: 2)
        XCTAssertEqual(r.state.cardPage, 0)
        r.categorize(["y": "public.app-category.games"])
        XCTAssertNotNil(r.state.lift, "the control: the lift survived the snapshot")
        XCTAssertEqual(r.state.cardPage, 0, "the page stayed")
        XCTAssertEqual(gapIndex(r), cap - 1, "the gap is on the shown page again, not back at the end of the list")
        r.state.pointerUp(point, time: time + 0.1)
        await waitUntil("the app joined") { r.state.folderApps.count == cap + 4 }
        XCTAssertEqual(r.placed, [.add("x", toFolder: folderID, relativeTo: "f\(cap - 2)", after: true)])
    }

    func testASnapshotLandingMidLiftOnTheLastPageKeepsTheGapThere() async {
        let cap = capacity
        let r = rig(folderApps: cap + 3)
        openedByALift(r)
        r.categorize(["y": "public.app-category.games"])
        XCTAssertEqual(r.state.cardPage, 1)
        XCTAssertEqual(gapIndex(r), cap + 3)
        let c = card(r, page: 1)
        r.state.pointerMoved(c.center(ofSlot: 0), time: 2)
        r.state.pointerUp(c.center(ofSlot: 0), time: 2.05)
        await waitUntil("the app joined") { r.state.folderApps.count == cap + 4 }
        XCTAssertEqual(r.state.folderApps.firstIndex { $0.id == "x" }, cap + 3, "released on the gap's own place: the end")
    }
}
