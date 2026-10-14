import XCTest
import SwiftUI
import AppKit
import HelmRuntime
import HelmTestSupport
@testable import HelmUI

/// `HelmPermissionStrip` is read against the block four pages write by hand: the
/// permission note with `HelmLayout.formInset` on the sides and `HelmSpace.s5`
/// above and below, a `Divider` under it, all inside the page's
/// `VStack(spacing: 0)` and shown only while the grant is `.denied`.
///
/// What is compared is the bitmap, not a size written out again here: the strip
/// and the hand-written block are rendered at one width, in a named appearance,
/// above the same marker view, and the two bitmaps have to be the same bytes.
/// The marker is a block of opaque red under the content, with the rest of the
/// stack's height below it; where its first row lands in the bitmap is the
/// height of everything above it, so the heights are read off the pixels and not
/// off a layout query.
///
/// Three things keep an equality from being two blank images. The hand-written
/// side is a fixture in this file, so it can differ from the strip. The `.denied`
/// render is required to have drawn something, which is a marker pushed below
/// the top of the bitmap and not the same bytes as the render with nothing above
/// the marker. And a fixture that is the block with its `Divider` taken out, or
/// drawn with other padding, has to be told apart from the strip, which is what
/// shows the byte comparison can see one rule's worth of difference.
///
/// Each drawing is read twice through `MountedRender.pixels`, after more turns
/// of the run loop, and the two readings must be the same bytes: a drawing that
/// moves between them fails the row there, whatever the comparison after it
/// says. The marker's row is read off one more capture, taken straight after
/// the second and compared with nothing.
///
/// The mount is `MountedRender`'s: a window that is built and never ordered in,
/// so nothing here reaches the screen or takes the key.
@MainActor
final class ThePermissionStripDrawsTheBlockThePagesWriteTests: XCTestCase {

    private static let width: CGFloat = 460
    private static let height: CGFloat = 220
    private static let sentence = "Needs Accessibility, or the pointer will not move"

    /// What a page draws today: the note, the form's inset on the sides, `s5`
    /// above and below, a `Divider` under it.
    private var theBlockByHand: some View {
        Group {
            HelmPermissionNote(need: .fullDiskAccess, text: Self.sentence)
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
            Divider()
        }
    }

    /// The block with its rule taken out: the fixture the comparison must tell
    /// from the strip.
    private var theBlockWithoutItsRule: some View {
        HelmPermissionNote(need: .fullDiskAccess, text: Self.sentence)
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    /// The block with the note flush against the sides: the other fixture.
    private var theBlockWithNoSideInset: some View {
        Group {
            HelmPermissionNote(need: .fullDiskAccess, text: Self.sentence)
                .padding(.vertical, HelmSpace.s5)
            Divider()
        }
    }

    private func strip(_ state: PermissionState?) -> some View {
        HelmPermissionStrip(need: .fullDiskAccess, state: state, text: Self.sentence)
    }

    private static let marker = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

    /// One drawing: its bytes, and the row, in pixels from the top, where the
    /// marker starts.
    private struct Still {
        let bytes: Data
        let markerRow: Int
        let pixelsHigh: Int
        let pixelsWide: Int
    }

    /// `content` in a `VStack(spacing: 0)` above the marker, mounted at one width
    /// and height in `appearance`, read twice through `MountedRender.pixels` and
    /// captured once more for the marker's row.
    private func still<V: View>(_ content: V, in appearance: NSAppearance.Name,
                                _ what: String, file: StaticString = #filePath,
                                line: UInt = #line) throws -> Still {
        let render = MountedRender(
            VStack(spacing: 0) {
                content
                Color(nsColor: Self.marker).frame(height: 10)
                Spacer(minLength: 0)
            },
            width: Self.width, height: Self.height, appearance: appearance)
        defer { render.drop() }
        render.settle(15)
        let first = try XCTUnwrap(render.pixels(), "\(what): no bitmap", file: file, line: line)
        render.settle(15)
        let second = try XCTUnwrap(render.pixels(), "\(what): no bitmap on the second reading",
                                   file: file, line: line)
        XCTAssertEqual(first, second,
                       "\(what) in \(RenderedInk.label(of: appearance)): the drawing was still moving",
                       file: file, line: line)
        // `RenderedInk.bytes` hands back bytes and no rep, and the row needs the rep's stride.
        let rep = try XCTUnwrap(render.host.bitmapImageRepForCachingDisplay(in: render.host.bounds),
                                "\(what): no bitmap rep", file: file, line: line)
        render.host.cacheDisplay(in: render.host.bounds, to: rep)
        let data = try XCTUnwrap(rep.bitmapData, "\(what): no bitmap data", file: file, line: line)
        XCTAssertEqual(rep.samplesPerPixel, 4, file: file, line: line)
        // Down column 0 nothing above the marker is opaque red: the hairline of a
        // `Divider` is not, and neither is the note where a fixture leaves it
        // flush against the side. So the first opaque red pixel is the marker.
        var row: Int?
        for y in 0..<rep.pixelsHigh {
            let at = y * rep.bytesPerRow
            if data[at] > 200, data[at + 1] < 60, data[at + 2] < 60, data[at + 3] == 255 {
                row = y
                break
            }
        }
        let found = try XCTUnwrap(row, "\(what) in \(RenderedInk.label(of: appearance)): the marker "
                                  + "was not drawn, so no height can be read", file: file, line: line)
        return Still(bytes: first, markerRow: found, pixelsHigh: rep.pixelsHigh,
                     pixelsWide: rep.pixelsWide)
    }

    func testADeniedStripIsTheBlockTheFourPagesWriteByHand() throws {
        for appearance in RenderedInk.bothAppearances {
            let name = RenderedInk.label(of: appearance)
            let empty = try still(EmptyView(), in: appearance, "nothing above the marker")
            let byHand = try still(theBlockByHand, in: appearance, "the block by hand")
            let drawn = try still(strip(.denied), in: appearance, "the denied strip")
            print("[strip] \(name): bitmap \(drawn.pixelsWide)x\(drawn.pixelsHigh) px, marker row: "
                  + "empty \(empty.markerRow), by hand \(byHand.markerRow), strip \(drawn.markerRow)")

            XCTAssertEqual(empty.markerRow, 0,
                           "\(name): the marker is not at the top with nothing above it")
            XCTAssertGreaterThan(byHand.markerRow, 0,
                                 "\(name): the block by hand drew nothing above the marker")
            XCTAssertGreaterThan(drawn.markerRow, empty.markerRow,
                                 "\(name): the denied strip drew nothing above the marker")
            XCTAssertNotEqual(drawn.bytes, empty.bytes,
                              "\(name): the denied strip is the render with nothing above the marker")

            XCTAssertEqual(drawn.markerRow, byHand.markerRow,
                           "\(name): the strip is \(drawn.markerRow) px tall, the block by hand "
                           + "\(byHand.markerRow)")
            XCTAssertEqual([drawn.pixelsWide, drawn.pixelsHigh], [byHand.pixelsWide, byHand.pixelsHigh],
                           "\(name): the two bitmaps are not the same size")
            XCTAssertEqual(drawn.bytes, byHand.bytes,
                           "\(name): the denied strip is not the block the pages write by hand")
        }
    }

    func testAStripThatIsGrantedOrNotReadDrawsNothingAboveTheMarker() throws {
        for appearance in RenderedInk.bothAppearances {
            let name = RenderedInk.label(of: appearance)
            let empty = try still(EmptyView(), in: appearance, "nothing above the marker")
            let denied = try still(strip(.denied), in: appearance, "the denied strip")
            let granted = try still(strip(.granted), in: appearance, "the granted strip")
            let notRead = try still(strip(nil), in: appearance, "the strip of a state not read")
            print("[strip] \(name): marker row: empty \(empty.markerRow), denied \(denied.markerRow), "
                  + "granted \(granted.markerRow), not read \(notRead.markerRow)")

            // The subject first: the strip does draw for a denied grant, so an
            // equality below is not two blank images.
            XCTAssertGreaterThan(denied.markerRow, 0, "\(name): the denied strip drew nothing")
            XCTAssertNotEqual(denied.bytes, empty.bytes, "\(name): the denied strip drew nothing")

            XCTAssertEqual(granted.markerRow, empty.markerRow, "\(name): a granted strip took room")
            XCTAssertEqual(notRead.markerRow, empty.markerRow, "\(name): a strip not read took room")
            XCTAssertEqual(granted.bytes, empty.bytes, "\(name): a granted strip drew something")
            XCTAssertEqual(notRead.bytes, empty.bytes, "\(name): a strip not read drew something")
        }
    }

    /// The probe for the first row: both sides of its equality are a drawing of
    /// the same note, so the equality would also hold if the comparison could not
    /// see a rule or a margin.
    func testTheComparisonTellsTheStripFromABlockMissingARuleOrAMargin() throws {
        for appearance in RenderedInk.bothAppearances {
            let name = RenderedInk.label(of: appearance)
            let drawn = try still(strip(.denied), in: appearance, "the denied strip")
            let noRule = try still(theBlockWithoutItsRule, in: appearance, "the block without its rule")
            let noInset = try still(theBlockWithNoSideInset, in: appearance, "the block with no side inset")
            print("[strip] \(name): marker row: strip \(drawn.markerRow), without rule "
                  + "\(noRule.markerRow), without inset \(noInset.markerRow)")

            XCTAssertNotEqual(drawn.bytes, noRule.bytes,
                              "\(name): the comparison cannot see the rule under the note")
            XCTAssertNotEqual(drawn.bytes, noInset.bytes,
                              "\(name): the comparison cannot see the side inset")
        }
    }
}
