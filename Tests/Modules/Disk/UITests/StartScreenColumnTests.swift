import XCTest
import SwiftUI
import HelmUI
@testable import Module_Disk_UI

/// The start screen sits on the same column as its own header.
///
/// `DiskDescriptor.pageBleeds` is true, so `HelmPageHeader` draws its plate at a
/// flat 20 pt across the whole pane — that flag exists because a centred header
/// walks away from full-bleed content as the window grows, and its doc comment
/// records the 203 pt it measured. The start state then asked for
/// `helmSettingsColumn()`, which caps at 744 pt and centres, so the cards were
/// the one phase of this page that did not start at 20: scanning and result
/// already do, and so does the permission note drawn directly above them.
///
/// Two tests, because neither is enough on its own: the first pins the shipped
/// page, the second measures what the two rules actually put on screen.
@MainActor
final class StartScreenColumnTests: XCTestCase {

    // MARK: - The shipped page

    func testAPageThatBleedsDoesNotPutItsContentInTheCentredColumn() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Modules/Disk/UI")
        let descriptor = try String(contentsOf: ui.appendingPathComponent("DiskDescriptor.swift"),
                                    encoding: .utf8)
        let page = try String(contentsOf: ui.appendingPathComponent("DiskSettingsPage.swift"),
                              encoding: .utf8)

        XCTAssertTrue(descriptor.contains("pageBleeds: Bool { true }"),
                      "precondition: the header draws at 20 pt across the pane")
        XCTAssertFalse(page.contains("helmSettingsColumn"), """
            The page's header bleeds to the pane's edge and this phase of it is \
            capped at 744 pt and centred, so the two disagree by half the \
            surplus — 32.5 pt at the default window, 202.5 pt at 1400.
            """)
    }

    // MARK: - What the two rules put on screen

    /// Measured rather than reasoned about: the leading edge of the real
    /// `HelmPageHeader` and the leading edge of content carrying each of the two
    /// chains, read off a rendered bitmap at both window widths.
    func testTheColumnAndTheHeaderStartAtTheSameX() throws {
        for pane in [Self.paneAtDefaultWindow, Self.paneAtWideWindow] {
            let header = try edge(of: Self.header, width: pane)
            let bleeding = try edge(of: Self.content(inColumn: false), width: pane)
            XCTAssertEqual(bleeding, header, accuracy: 1,
                           "at a \(Int(pane)) pt pane the content starts at \(bleeding) "
                           + "and its header at \(header)")
        }
    }

    /// The control: the chain that was shipped does not agree with the header,
    /// and by how much. A measurement that cannot tell the two apart would pass
    /// whatever the page does.
    func testTheCentredColumnIsWhereTheHeaderIsNot() throws {
        let expected: [CGFloat: CGFloat] = [Self.paneAtDefaultWindow: 32.5,
                                            Self.paneAtWideWindow: 202.5]
        for (pane, drift) in expected {
            let header = try edge(of: Self.header, width: pane)
            let centred = try edge(of: Self.content(inColumn: true), width: pane)
            XCTAssertEqual(centred - header, drift, accuracy: 1.5,
                           "at a \(Int(pane)) pt pane the centred column starts "
                           + "\(centred - header) pt right of the header")
        }
    }

    // MARK: - Fixtures

    /// The detail pane at the app's default 1060 pt window, and at 1400 — the
    /// width `HelmPageHeader`'s own comment measured its 203 pt at.
    private static let paneAtDefaultWindow: CGFloat = 809
    private static let paneAtWideWindow: CGFloat = 1149

    private static var header: some View {
        HelmPageHeader(symbol: "chart.pie", tint: .blue,
                       title: "Disk", subtitle: "What is taking up space", bleeds: true)
    }

    /// A marker carrying the page's own padding and, optionally, the column.
    /// Opaque so the edge is unambiguous — the card's fill is 3.5% and the
    /// question here is where it starts, not what it looks like.
    @ViewBuilder private static func content(inColumn: Bool) -> some View {
        let marker = Color.black.frame(height: 40).padding(20)
        if inColumn { marker.helmSettingsColumn() } else { marker }
    }

    /// The x of the first column holding anything but the background.
    private func edge(of view: some View, width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width).background(.white))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "SwiftUI rendered nothing")
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        for x in 0..<image.width {
            for y in 0..<image.height {
                let offset = y * bytesPerRow + x * 4
                let ink = 255 - min(pixels[offset], min(pixels[offset + 1], pixels[offset + 2]))
                // Well above antialiasing at the edge of a glyph, well below the
                // marker and the icon plate.
                if ink > 60 { return CGFloat(x) }
            }
        }
        throw XCTSkip("nothing was drawn at \(width) pt")
    }
}
