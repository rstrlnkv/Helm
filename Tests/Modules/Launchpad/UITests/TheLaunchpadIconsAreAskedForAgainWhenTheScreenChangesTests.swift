import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_UI

/// The system says a window's backing properties changed also when its scale did not (a colour space, the first ordering on screen):
/// icons under way then must land, not be dropped. When the scale did change, what was drawn is drawn again, and nothing outside the
/// cache says to draw: its own redraw makes the views ask the slots again. A counting fake stands for the drawing (the port is
/// `LaunchpadIcons.Renderer`, named at every construction).
@MainActor
final class TheLaunchpadIconsAreAskedForAgainWhenTheScreenChangesTests: XCTestCase {
    private final class Drawing: @unchecked Sendable {
        let finished = Locked(0)
        private let gate: DispatchSemaphore?
        init(held: Bool = false) { gate = held ? DispatchSemaphore(value: 0) : nil }
        func release(_ times: Int = 1) { for _ in 0..<times { gate?.signal() } }
        var renderer: LaunchpadIcons.Renderer {
            { [self] _, pixels in
                gate?.wait()
                defer { finished.withLock { $0 += 1 } }
                guard let context = CGContext(data: nil, width: min(pixels, 64), height: min(pixels, 64), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                return context.makeImage()
            }
        }
    }

    private let paths = ["/Applications/a.app", "/Applications/b.app", "/Applications/c.app"]

    private func state(_ drawing: Drawing) -> (LaunchpadScreenState, LaunchpadIcons) {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
        let icons = LaunchpadIcons(capacity: g.capacity, side: g.icon, scale: 2, render: drawing.renderer)
        return (LaunchpadScreenState(geometry: g, icons: icons), icons)
    }

    func testARescaleToTheSameScaleKeepsWhatIsUnderWay() async {
        let drawing = Drawing(held: true)
        let (state, icons) = state(drawing)
        for path in paths { _ = icons.image(for: path, side: 32) }
        state.rescale(2)
        drawing.release(3)
        await waitUntil("what was under way landed") { icons.rendered == 3 }
        XCTAssertEqual(icons.rendered, 3, "a notification that changed no scale dropped the icons being drawn")
    }

    func testARescaleToANewScaleEndsWithEverySlotAskedFilledAndNoRedrawFromOutside() async {
        let drawing = Drawing()
        let (state, icons) = state(drawing)
        let ask = { for path in self.paths { _ = icons.image(for: path, side: 32) } }
        icons.onArrival = ask
        ask()
        await waitUntil("drawn at 2x") { icons.rendered == 3 }
        // The redraw the landings said has been said: the next one is the rescale's own.
        try? await Task.sleep(for: .milliseconds(150))
        state.rescale(3)
        await waitUntil("every slot asked is drawn again at 3x, with no redraw said from outside") { icons.rendered == 6 }
        XCTAssertEqual(icons.rendered, 6)
        XCTAssertEqual(icons.scale, 3)
    }
}
