import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A timed area is cut whole from the display as it is after the countdown, or refused in words, and the line between
/// the two is the display's own edge.** The rectangle is drawn on the first freeze and cut from the second. A display
/// that no longer holds all of it is `displayGone`, told on the toast with nothing written; a rectangle that touches the
/// edge, a display that grew, and a scale that changed under the same size in points are not refusals. The toast is read
/// through the controller (`PanelRig.refusalBody`), so "nothing was written" is never the whole of a claim.
@MainActor
final class TheShrunkDisplayIsRefusedByNameAndTheEdgeIsNotTests: XCTestCase {
    private var boxes: [PanelRig.Rig] = []
    override func tearDown() {
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    /// A timed area drawn at `area` on the first freeze, the second freeze shaped by `shape`; ends when the machine is free.
    private func timed(area: CGRect, firstScale: CGFloat = 1,
                       _ shape: @escaping @Sendable (_ frame: FrozenDisplay) -> FrozenDisplay) async throws -> PanelRig.Rig {
        let box = try PanelRig.rig(timer: .five)
        boxes.append(box)
        let paint = box.screen.shape
        box.screen.shape = { n, frames in
            let painted = paint(n, frames)
            if n == 1 {
                return firstScale == 1 ? painted : painted.map {
                    FrozenDisplay(id: $0.id, frame: $0.frame, scale: firstScale,
                                  image: PanelRig.paint(1, width: Int($0.frame.width * firstScale), height: Int($0.frame.height * firstScale)),
                                  uuid: $0.uuid)
                }
            }
            return painted.map(shape)
        }
        box.controller.begin(.panel)
        box.controller.bar.model.choose(.area)
        await waitUntil("the overlay opened") { box.held.overlay != nil }
        PanelRig.drag(try XCTUnwrap(box.held.overlay), on: box.display, area)
        box.controller.capture(from: .area)
        await waitUntil("the second freeze was taken") { box.screen.freezes == 2 }
        await waitUntil("the machine was freed") { !box.controller.isBusy }
        return box
    }

    private nonisolated static func resized(_ frame: FrozenDisplay, width: CGFloat, height: CGFloat, scale: CGFloat? = nil) -> FrozenDisplay {
        let scale = scale ?? frame.scale
        return FrozenDisplay(id: frame.id, frame: CGRect(x: frame.frame.minX, y: frame.frame.minY, width: width, height: height),
                             scale: scale, image: PanelRig.paint(2, width: Int(width * scale), height: Int(height * scale)),
                             uuid: frame.uuid)
    }

    func testARectangleExactlyAtTheDisplaysEdgeIsNotRefused() async throws {
        let edge = CGRect(x: 600, y: 500, width: 400, height: 300)
        let box = try await timed(area: edge) { $0 }
        XCTAssertTrue(PanelRig.hasToast(box.controller))
        XCTAssertEqual(box.disk.written, 1, "a rectangle that touches the edge of the display was refused")
        XCTAssertEqual(PanelRig.size(of: box.disk.last), edge.size)
        XCTAssertNil(PanelRig.refusalBody(of: box.controller), "a rectangle at the edge was refused in words")
    }

    func testARectangleHalfAPointPastTheEdgeAfterTheDisplayShrankIsRefused() async throws {
        let edge = CGRect(x: 600, y: 500, width: 400, height: 300)
        let box = try await timed(area: edge) { Self.resized($0, width: 999.5, height: 800) }
        XCTAssertEqual(box.disk.written, 0, "the rectangle lies half a point off the display and was cut")
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.displayGone))
    }

    func testADisplayThatShrankOnlyInHeightIsRefusedToo() async throws {
        let box = try await timed(area: PanelRig.area) { Self.resized($0, width: 1000, height: 300) }
        XCTAssertEqual(box.disk.written, 0)
        XCTAssertEqual(PanelRig.refusalBody(of: box.controller), ScStr.refusal(.displayGone))
    }

    func testADisplayThatGrewDeliversTheWholeRectangleAndNoRefusal() async throws {
        let box = try await timed(area: PanelRig.area) { Self.resized($0, width: 2000, height: 1600) }
        XCTAssertEqual(box.disk.written, 1, "a display that grew lost the shot")
        XCTAssertEqual(PanelRig.size(of: box.disk.last), PanelRig.area.size)
        XCTAssertNil(PanelRig.refusalBody(of: box.controller))
    }

    /// The same size in points at another scale: the rectangle is in points, so it is whole, at the new scale's pixels.
    func testAScaleThatChangedFromTwoToOneKeepsTheRectangleInPoints() async throws {
        let box = try await timed(area: PanelRig.area, firstScale: 2) { Self.resized($0, width: 1000, height: 800, scale: 1) }
        XCTAssertEqual(box.disk.written, 1, "a change of scale lost the shot")
        XCTAssertEqual(PanelRig.size(of: box.disk.last), PanelRig.area.size, "the rectangle is not whole in points at scale 1")
        XCTAssertNil(PanelRig.refusalBody(of: box.controller))
    }

    func testAScaleThatChangedFromOneToTwoKeepsTheRectangleInPoints() async throws {
        let box = try await timed(area: PanelRig.area) { Self.resized($0, width: 1000, height: 800, scale: 2) }
        XCTAssertEqual(box.disk.written, 1)
        XCTAssertEqual(PanelRig.size(of: box.disk.last), CGSize(width: PanelRig.area.width * 2, height: PanelRig.area.height * 2),
                       "the rectangle is not whole in points at scale 2")
        XCTAssertNil(PanelRig.refusalBody(of: box.controller))
    }
}
