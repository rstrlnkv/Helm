import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The window's icons are drawn once per (path, pixel side), off main, into a bitmap of exactly that side: one representation, not the
/// system's (32 for Safari, Calendar and Finder on macOS 27.3) with another bitmap added inside it for every size a view asked for. A render still running when the window
/// closes lands nowhere. A counting fake stands for the drawing (the port is `LaunchpadIcons.Renderer`, named at every construction);
/// the last test draws a real app's icon through the system's own.
@MainActor
final class TheLaunchpadIconsAreRenderedOnceAtTheirSizeTests: XCTestCase {
    /// Counts what is asked of it, per key, and may be held inside the drawing until the test lets it go.
    private final class Drawing: @unchecked Sendable {
        let asked = Locked<[String: Int]>([:])
        let finished = Locked(0)
        let inside = Locked(0)
        private let gate: DispatchSemaphore?
        init(held: Bool = false) { gate = held ? DispatchSemaphore(value: 0) : nil }
        func release() { gate?.signal() }

        var renderer: LaunchpadIcons.Renderer {
            { [self] path, pixels in
                asked.withLock { $0["\(pixels)|\(path)", default: 0] += 1 }
                inside.withLock { $0 += 1 }
                gate?.wait()
                defer { finished.withLock { $0 += 1 } }
                guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
                return context.makeImage()
            }
        }
        var total: Int { asked.withLock { $0.values.reduce(0, +) } }
    }

    /// The width in pixels of the bitmap the one representation holds (the representation's own `pixelsWide` follows the screen's scale, not the bitmap's).
    private static func bitmapWidth(_ image: NSImage?) -> Int? {
        guard let image, image.representations.count == 1 else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width
    }

    /// Asks until the image at exactly this side is there (not the one of another size a miss answers meanwhile), as a view does on each draw after an arrival.
    private func drawn(_ icons: LaunchpadIcons, _ path: String, side: CGFloat, scale: CGFloat = 2) async -> NSImage? {
        var found: NSImage?
        await waitUntil("the icon for \(path) at \(side) landed") {
            found = icons.image(for: path, side: side)
            return Self.bitmapWidth(found) == Int(side * scale)
        }
        return found
    }

    func testManyAsksForOnePathAndSideDrawItOnceInOneRepresentationAtItsPointSize() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 10, side: 80, scale: 2, render: drawing.renderer)
        for _ in 0..<30 { _ = icons.image(for: "/Applications/a.app", side: 32) }
        let image = await drawn(icons, "/Applications/a.app", side: 32)
        for _ in 0..<30 { _ = icons.image(for: "/Applications/a.app", side: 32) }
        XCTAssertEqual(drawing.total, 1, "one path at one side is one drawing, however many views asked and however often they drew")
        XCTAssertEqual(image?.representations.count, 1, "the image is one bitmap")
        XCTAssertEqual(Self.bitmapWidth(image), 64, "the bitmap is the side in pixels")
        XCTAssertEqual(image?.size, NSSize(width: 32, height: 32), "its size is the pixels over the scale, in points")
    }

    func testFourSidesOfOnePathAreFourDrawings() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 10, side: 80, scale: 2, render: drawing.renderer)
        for side: CGFloat in [16, 24, 40, 64] { _ = await drawn(icons, "/Applications/a.app", side: side) }
        XCTAssertEqual(drawing.total, 4, "a tile, a quadrant, a folder cell and a cluster icon are four sizes, drawn once each")
        XCTAssertEqual(Set(drawing.asked.value.keys), ["32|/Applications/a.app", "48|/Applications/a.app", "80|/Applications/a.app", "128|/Applications/a.app"])
    }

    func testAnIconStillBeingDrawnWhenTheWindowClosesLandsNowhere() async {
        let drawing = Drawing(held: true)
        let icons = LaunchpadIcons(capacity: 10, side: 80, scale: 2, render: drawing.renderer)
        let arrivals = Locked(0)
        icons.onArrival = { arrivals.withLock { $0 += 1 } }
        _ = icons.image(for: "/Applications/a.app", side: 32)
        await waitUntil("the drawing is under way") { drawing.inside.value == 1 }
        icons.removeAll()
        drawing.release()
        await waitUntil("the drawing has finished") { drawing.finished.value == 1 }
        // Let main's queue run what the finished drawing posted, if it posted anything.
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(icons.rendered, 0, "a result that came after the window closed was kept")
        XCTAssertEqual(arrivals.value, 0, "a result that came after the window closed said so")
    }

    func testANewScaleDrawsEverythingAgainAtItsOwnPixels() async {
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: 10, side: 80, scale: 2, render: drawing.renderer)
        let first = await drawn(icons, "/Applications/a.app", side: 32)
        XCTAssertEqual(first?.size, NSSize(width: 32, height: 32))
        icons.reconfigure(capacity: 10, side: 80, scale: 3)
        let again = await drawn(icons, "/Applications/a.app", side: 32, scale: 3)
        XCTAssertEqual(again?.size, NSSize(width: 32, height: 32), "the same points, more pixels")
        XCTAssertEqual(drawing.asked.value, ["64|/Applications/a.app": 1, "96|/Applications/a.app": 1])
    }

    func testTheFirstSnapshotWaitsForPageZerosIconsAndThenLands() async {
        let rig = LiftRig(self, apps: ["a", "b", "c"])
        let drawing = Drawing()
        let icons = LaunchpadIcons(capacity: rig.g.capacity, side: 80, scale: 2, render: drawing.renderer)
        let state = LaunchpadScreenState(geometry: rig.g, icons: icons)
        let report = Locked<(drawn: Int, timedOut: Bool)?>(nil)
        state.onIconsWarmed = { _, drawn, _, timedOut in report.value = (drawn, timedOut) }
        state.update(snapshot: rig.engine.read(reason: .refresh))
        XCTAssertEqual(state.mode, .busy, "the first picture is not published before its icons are")
        await waitUntil("the snapshot landed") { state.mode == .grid }
        XCTAssertEqual(drawing.total, 3, "page 0's three apps were drawn at the grid's icon side")
        XCTAssertEqual(report.value?.drawn, 3)
        XCTAssertEqual(report.value?.timedOut, false)
    }

    func testTheFirstSnapshotLandsAtTheDeadlineWhenTheIconsAreLate() async {
        let rig = LiftRig(self, apps: ["a"])
        let drawing = Drawing(held: true)
        let icons = LaunchpadIcons(capacity: rig.g.capacity, side: 80, scale: 2, render: drawing.renderer)
        let state = LaunchpadScreenState(geometry: rig.g, icons: icons)
        let report = Locked<(drawn: Int, timedOut: Bool)?>(nil)
        state.onIconsWarmed = { _, drawn, _, timedOut in report.value = (drawn, timedOut) }
        state.update(snapshot: rig.engine.read(reason: .refresh))
        await waitUntil("the snapshot landed without its icons") { state.mode == .grid }
        XCTAssertEqual(report.value?.timedOut, true, "the deadline ended the wait")
        XCTAssertEqual(report.value?.drawn, 0)
        drawing.release()
        state.shutdown()
        icons.removeAll()
    }

    func testTheSystemsOwnDrawingGivesABitmapOfTheAskedSideThatIsNotBlank() async throws {
        let icons = LaunchpadIcons(capacity: 4, side: 80, scale: 2)
        let image = await drawn(icons, "/System/Library/CoreServices/Finder.app", side: 32)
        XCTAssertEqual(Self.bitmapWidth(image), 64)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image?.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let ink = (0..<64).contains { y in (0..<64).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 } }
        XCTAssertTrue(ink, "the bitmap has something drawn in it")
    }
}
