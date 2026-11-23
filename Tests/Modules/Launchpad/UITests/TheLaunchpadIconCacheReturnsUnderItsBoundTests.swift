import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// An arrival never evicts what the last redraw asked, so a long session of page flips must still come back under the bound: what was
/// protected is what was asked since the last redraw was said, and the next redraw lets it go. The bound is read through what it does:
/// after many pages, asking the early ones again draws them again (they were let go), and the last pages are still held (no draw).
/// A counting fake stands for the drawing (the port is `LaunchpadIcons.Renderer`, named at every construction).
@MainActor
final class TheLaunchpadIconCacheReturnsUnderItsBoundTests: XCTestCase {
    private final class Drawing: @unchecked Sendable {
        let asked = Locked(0)
        let finished = Locked(0)
        private let answers: Bool
        init(answers: Bool = true) { self.answers = answers }
        var renderer: LaunchpadIcons.Renderer {
            { [self] _, pixels in
                asked.withLock { $0 += 1 }
                defer { finished.withLock { $0 += 1 } }
                guard answers else { return nil }
                guard let context = CGContext(data: nil, width: min(pixels, 32), height: min(pixels, 32), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
                context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                return context.makeImage()
            }
        }
    }

    /// Quiet: nothing asked or landed over three reads 25 ms apart, and every drawing asked has finished (a bounded wait, not a read of one instant).
    private func quiet(_ icons: LaunchpadIcons, _ drawing: Drawing) async {
        var same = 0, last = (-1, -1)
        for _ in 0..<400 where same < 3 {
            try? await Task.sleep(for: .milliseconds(25))
            let now = (drawing.asked.value, icons.rendered)
            same = now == last && drawing.finished.value == drawing.asked.value ? same + 1 : 0
            last = now
        }
        XCTAssertLessThan(same < 3 ? 1 : 0, 1, "the cache never went quiet")
    }

    private func path(_ page: Int, _ i: Int) -> String { "/Applications/p\(page)-\(i).app" }

    /// Flips to `page`: the page's keys are asked, and each redraw (an arrival's say) asks the shown page again, as the screen does.
    private func flip(to page: Int, keys: Int, side: CGFloat, icons: LaunchpadIcons, drawing: Drawing) async {
        let ask = { for i in 0..<keys { _ = icons.image(for: self.path(page, i), side: side) } }
        icons.onArrival = ask
        ask()
        await quiet(icons, drawing)
    }

    private func drawnAgain(pages: Range<Int>, keys: Int, side: CGFloat, icons: LaunchpadIcons, drawing: Drawing) async -> Int {
        let before = drawing.asked.value
        icons.onArrival = nil
        for page in pages { for i in 0..<keys { _ = icons.image(for: path(page, i), side: side) } }
        await quiet(icons, drawing)
        return drawing.asked.value - before
    }

    /// Capacity 1: the bound is 30 keys, three pages of ten. Forty pages go by; the first thirty are let go, the last three are held.
    func testALongSessionOfPageFlipsLeavesTheCountBoundHonoured() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 1, side: 80, scale: 2, render: drawing.renderer)
        for page in 0..<40 { await flip(to: page, keys: 10, side: 16, icons: icons, drawing: drawing) }
        XCTAssertEqual(drawing.asked.value, 400, "a flip drew something twice: the redraw asked what had just been evicted")
        let last = await drawnAgain(pages: 37..<40, keys: 10, side: 16, icons: icons, drawing: drawing)
        XCTAssertEqual(last, 0, "the last three pages (the bound) were not held")
        let early = await drawnAgain(pages: 0..<30, keys: 10, side: 16, icons: icons, drawing: drawing)
        XCTAssertGreaterThanOrEqual(early, 300 - 30, "after forty flips more than the bound (30 keys) is still held: \(300 - early) of the first 300 keys")
    }

    /// The same by bytes: capacity 1 at 80 pt, 2x is 614 400 bytes, six bitmaps of 160 px; pages of three, thirty of them.
    func testALongSessionOfPageFlipsLeavesTheByteBoundHonoured() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 1, side: 80, scale: 2, render: drawing.renderer)
        for page in 0..<30 { await flip(to: page, keys: 3, side: 80, icons: icons, drawing: drawing) }
        // The last ten pages are 30 keys, inside the count bound (30) and far over the byte bound (six): only the byte bound lets the older go.
        let recent = await drawnAgain(pages: 20..<30, keys: 3, side: 80, icons: icons, drawing: drawing)
        XCTAssertGreaterThanOrEqual(recent, 30 - 6, "more than six bitmaps of 160 px are still held: \(30 - recent) of the last 30 keys")
    }

    /// No redraw is ever said (`onArrival` nil: the window's state is gone, or the cache is reused after `removeAll`): protection must not
    /// hold everything for ever.
    func testWithNoOneToSayARedrawToTheCacheStillLetsGo() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 1, side: 80, scale: 2, render: drawing.renderer)
        icons.removeAll()
        XCTAssertNil(icons.onArrival)
        for page in 0..<40 {
            for i in 0..<10 { _ = icons.image(for: path(page, i), side: 16) }
            await quiet(icons, drawing)
        }
        let early = await drawnAgain(pages: 0..<30, keys: 10, side: 16, icons: icons, drawing: drawing)
        XCTAssertGreaterThanOrEqual(early, 300 - 30, "a cache with no one to redraw holds \(300 - early) of the first 300 keys: protected for ever")
    }

    /// One burst over the bound lands in one turn (nothing can be let go yet); the next single arrival trims it back.
    func testABurstOverTheBoundIsTrimmedByTheNextArrival() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 1, side: 80, scale: 2, render: drawing.renderer)
        for i in 0..<120 { _ = icons.image(for: path(0, i), side: 16) }
        await quiet(icons, drawing)
        XCTAssertEqual(icons.rendered, 120)
        _ = icons.image(for: path(1, 0), side: 16)
        await quiet(icons, drawing)
        XCTAssertEqual(icons.rendered, 121)
        let early = await drawnAgain(pages: 0..<1, keys: 120, side: 16, icons: icons, drawing: drawing)
        XCTAssertGreaterThanOrEqual(early, 120 - 29, "after one more arrival \(120 - early) of the burst's 120 keys are still held (bound 30)")
    }

    /// Nothing ever lands: the failed keys are not held as images and a new window of asks is bounded by the asks.
    func testWhenNothingEverLandsNothingIsHeldAndNothingIsAskedTwice() async {
        let drawing = Drawing(answers: false)
        let icons = LaunchpadIcons(capacity: 1, side: 80, scale: 2, render: drawing.renderer)
        for page in 0..<20 {
            for i in 0..<10 { _ = icons.image(for: path(page, i), side: 16) }
            await quiet(icons, drawing)
        }
        XCTAssertEqual(icons.rendered, 0)
        XCTAssertEqual(drawing.asked.value, 200)
        for page in 0..<20 { for i in 0..<10 { XCTAssertNil(icons.image(for: path(page, i), side: 16)) } }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(drawing.asked.value, 200, "a failed key was asked again")
    }
}
