import CoreGraphics
import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **A remembered area opens an overlay only on the display it was drawn on,
/// and only as much of it as is still there.** The record sits in a property
/// list any process running as the user can write, and it is a reading made on
/// one desk: read on another — a display gone, one that came back smaller, a
/// number that is not a number — it opens the overlay empty and never a
/// selection hanging off the screen.
final class TheRememberedSelectionLandsOnlyWhereItFitsTests: XCTestCase {

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    private func record(display: Any = "AAAA-1111", x: Any = 100.0, y: Any = 50.0,
                        width: Any = 300.0, height: Any = 200.0) -> [String: Any] {
        [RememberedSelection.Key.display: display, RememberedSelection.Key.x: x, RememberedSelection.Key.y: y,
         RememberedSelection.Key.width: width, RememberedSelection.Key.height: height]
    }

    private func screen(_ uuid: String?, id: UInt32 = 1, width: CGFloat = 1000, height: CGFloat = 800) throws -> FrozenDisplay {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return FrozenDisplay(id: DisplayID(id), frame: CGRect(x: 0, y: 0, width: width, height: height), scale: 2,
                             image: try XCTUnwrap(context.makeImage()), uuid: uuid)
    }

    func testARecordComesBackAsWritten() throws {
        let kept = store()
        let written = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 10, y: 20, width: 300, height: 200)))
        written.write(to: kept)
        XCTAssertEqual(RememberedSelection.read(kept), written)
        let landing = try XCTUnwrap(written.landing(in: [try screen("AAAA-1111")]))
        XCTAssertEqual(landing.rect, written.rect, "a selection that fits was cut")
    }

    /// Every way a stored number can be something other than a length. The
    /// control is the same record with sane values, so an absence is only worth
    /// something beside it.
    func testNothingThatIsNotANumberOrALengthIsARecord() {
        XCTAssertNotNil(RememberedSelection.read(store(record())), "the control record was refused")
        let bad: [(String, [String: Any])] = [
            ("NaN x", record(x: Double.nan)),
            ("infinite width", record(width: Double.infinity)),
            ("NaN height", record(height: Double.nan)),
            ("zero width", record(width: 0.0)),
            ("half a point", record(height: 0.5)),
            ("negative width", record(width: -300.0)),
            ("a string for x", record(x: "100")),
            ("a bool for y", record(y: true)),
            ("no display", record(display: "")),
            ("a display that is not a string", record(display: 7)),
            ("a UUID of a thousand characters", record(display: String(repeating: "A", count: 1000))),
        ]
        for (what, values) in bad {
            XCTAssertNil(RememberedSelection.read(store(values)), what)
        }
        for missing in [RememberedSelection.Key.x, RememberedSelection.Key.height, RememberedSelection.Key.display] {
            var partial = record()
            partial[missing] = nil
            XCTAssertNil(RememberedSelection.read(store(partial)), "a record without \(missing) was read")
        }
    }

    /// The largest integer a plist can hold, and numbers no display has.
    func testAHugeNumberIsBoundedAndNeverReachesTheDisplayOutsideIt() throws {
        let huge = try XCTUnwrap(RememberedSelection.read(store(record(x: Int.max, y: Int.min, width: Int.max, height: Int.max))))
        XCTAssertLessThanOrEqual(abs(huge.rect.minX), RememberedSelection.ceiling)
        XCTAssertLessThanOrEqual(huge.rect.width, RememberedSelection.ceiling)
        // x at the ceiling is far to the right of any display.
        XCTAssertNil(huge.landing(in: [try screen("AAAA-1111")]))
        // A huge extent from a sane origin is the whole display, cut to it.
        let wide = try XCTUnwrap(RememberedSelection.read(store(record(x: 0, y: 0, width: Int.max, height: 1e300))))
        XCTAssertEqual(try XCTUnwrap(wide.landing(in: [try screen("AAAA-1111")])).rect,
                       CGRect(x: 0, y: 0, width: 1000, height: 800))
    }

    func testItLandsOnTheDisplayWithItsUUIDAndOnNoOther() throws {
        let selection = try XCTUnwrap(RememberedSelection(display: "BBBB-2222", rect: CGRect(x: 10, y: 10, width: 100, height: 100)))
        let frames = [try screen("AAAA-1111", id: 1), try screen("BBBB-2222", id: 9)]
        XCTAssertEqual(selection.landing(in: frames)?.display, DisplayID(9), "found by the id, not the UUID")
        XCTAssertNil(selection.landing(in: [try screen("AAAA-1111", id: 1)]), "a foreign display took the record")
        XCTAssertNil(selection.landing(in: [try screen(nil, id: 1)]), "a display with no UUID took the record")
        XCTAssertNil(selection.landing(in: []))
    }

    func testOnlyThePartThatStillFitsIsKeptAndASliverIsNone() throws {
        let selection = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 100, y: 100, width: 800, height: 600)))
        let smaller = try XCTUnwrap(selection.landing(in: [try screen("AAAA-1111", width: 500, height: 400)]))
        XCTAssertEqual(smaller.rect, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertNil(selection.landing(in: [try screen("AAAA-1111", width: 100, height: 100)]),
                     "a display that no longer reaches the selection still got one")
        XCTAssertNil(selection.landing(in: [try screen("AAAA-1111", width: 100.5, height: 900)]),
                     "half a point of selection is not one")
        let hanging = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: -50, y: 10, width: 200, height: 100)))
        XCTAssertEqual(hanging.landing(in: [try screen("AAAA-1111")])?.rect, CGRect(x: 0, y: 10, width: 150, height: 100))
        let outside = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: -500, y: 10, width: 100, height: 100)))
        XCTAssertNil(outside.landing(in: [try screen("AAAA-1111")]))
    }
}
