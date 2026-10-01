import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The SSH tab's plain-text box is a well with its text inset, and nothing
/// of the text view's own fill shows beside it.**
///
/// A `TextEditor` paints `textBackgroundColor` edge to edge, which read as a
/// band under the header — a slab, near-black in dark, running past the page's
/// column to the window's edges — with the first glyph a few points from the
/// left edge and the first line on the top. Read off the mounted page:
///
/// - the box is one rounded layer taller than a control, as the Homebrew
///   console's is; with the platform fill showing there is none;
/// - the gutter beside it holds only the pane, so the slab cannot be back;
/// - the text keeps `HostsSettingsPage.textBoxInset` from the box at the top
///   and the left, and the band just inside the margin holds ink, so a clear
///   margin cannot be an empty box.
///
/// Both appearances are read; the file is the wire's own, unwritable, so the
/// refusal banner is above the box, as it is for a file outside the home.
@MainActor
final class ThePlainTextBoxIsInsetAtTheTopAndTheLeftTests: XCTestCase {
    private var wire: HostsUIWire?
    private var render: MountedRender?

    override func tearDown() async throws {
        await MainActor.run { self.render?.drop(); self.render = nil; self.wire = nil }
    }

    private func mount(_ appearance: NSAppearance.Name) -> MountedRender {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        wire = hosted
        let mounted = MountedRender(HostsSettingsPage(vm: hosted.vm, opensOnSSHText: true),
                                    width: 900, height: 500, appearance: appearance)
        render = mounted
        mounted.settle(40)
        return mounted
    }

    /// The box: the one rounded layer taller than a control.
    private func box(_ mount: MountedRender) throws -> CGRect {
        guard let root = mount.host.layer else { throw XCTSkip("no layer tree") }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > 100 {
                found.append(layer.convert(layer.bounds, to: root))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        XCTAssertEqual(found.count, 1, "\(found.count) block-sized wells drew, the text box is one")
        let frame = try XCTUnwrap(found.first)
        let top = root.isGeometryFlipped ? frame.minY : mount.host.bounds.height - frame.maxY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
    }

    func testTheTextViewsOwnFillDoesNotShowBesideTheBox() throws {
        for appearance in RenderedInk.bothAppearances {
            let mounted = mount(appearance)
            let box = try box(mounted)
            let rows = Int(box.minY.rounded(.up)) + 8...Int(box.maxY.rounded(.down)) - 8
            let gutter = 0...Int((box.minX - 4).rounded(.down))
            let beside = try XCTUnwrap(RenderedInk.read(mounted.host, points: rows, columns: gutter))
            XCTAssertEqual(beside, 0, """
                \(RenderedInk.label(of: appearance)): something is drawn between the window's \
                edge and the box — the text view's own fill, which is the band under the header
                """)
        }
    }

    func testTheTextKeepsItsInsetFromTheTopAndTheLeft() throws {
        let inset = HostsSettingsPage.textBoxInset
        for appearance in RenderedInk.bothAppearances {
            let mounted = mount(appearance)
            let box = try box(mounted)
            func ink(top: Bool, from near: CGFloat, to far: CGFloat) throws -> Int {
                let corner = HelmRadius.card
                let rows = top ? Int((box.minY + near).rounded(.up))...Int((box.minY + far).rounded(.down))
                    : Int((box.minY + corner).rounded(.up))...Int((box.minY + corner + 20).rounded(.down))
                let columns = top ? Int((box.minX + corner).rounded(.up))...Int((box.maxX - corner).rounded(.down))
                    : Int((box.minX + near).rounded(.up))...Int((box.minX + far).rounded(.down))
                return try XCTUnwrap(RenderedInk.read(mounted.host, points: rows, columns: columns))
            }
            for top in [true, false] {
                let edge = top ? "top" : "left"
                XCTAssertGreaterThan(try ink(top: top, from: inset + 1, to: inset + 12), 0,
                                     "\(RenderedInk.label(of: appearance)): nothing drew just inside the \(edge) margin")
                XCTAssertEqual(try ink(top: top, from: 2, to: inset - 1), 0,
                               "\(RenderedInk.label(of: appearance)): the text reaches into the \(inset) pt at the \(edge) edge")
            }
        }
    }
}
