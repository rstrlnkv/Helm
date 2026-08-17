// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import AppKit
import SwiftUI
import HelmUI
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The popover behind the right-hand door: two questions, two pictures, and one
/// right edge for every control in it.
///
/// It was 483 pt of six previews in two rhythms; the ceiling below is what the
/// C2 render measured plus room for a language that needs another line. A
/// popover is a window macOS orders in, so this mounts `noticesPopover`
/// directly — the same view the door presents.
///
/// **Neither control is an `NSPopUpButton` on this system.** SwiftUI draws a
/// `.menu` picker itself now: what AppKit puts in the tree is a `_FocusRingView`
/// at the control's own frame, with the bezel a `CALayer` of the same frame
/// underneath it. The switch is real (`PlatformSwitch: NSSwitch`), so the two
/// readings are the ring for the pickers and the control for the switch — and
/// both are the frame the person sees, which is what a shared right edge means.
@MainActor
final class TheNoticesPopoverEndsOnOneEdgeTests: XCTestCase {

    private func card() -> VPNConnectionCard {
        VPNConnectionCard(
            connection: VPNConnection(id: "1", name: "incy", status: .connected, kind: "VPN"),
            strip: VPNTenants.Strip(all: []),
            timings: [:],
            heldByHelm: false,
            notice: .menuBar,
            dropNotice: .system,
            spin: true,
            tintUp: "green",
            tintDown: "orange",
            bannerAuthorization: nil,
            elsewhere: [],
            connect: {}, disconnect: {}, addApp: {},
            setTiming: { _, _ in }, move: { _, _ in }, remove: { _ in },
            setNotice: { _ in }, setDropNotice: { _ in },
            setSpin: { _ in }, setTint: { _, _ in })
    }

    /// Held, so the teardown can let go of the window: one left holding a
    /// hosting view holds the view behind it too (`MountedRender.drop`).
    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private func mount() -> MountedRender {
        let render = MountedRender(card().noticesPopover, width: 420, height: 900,
                                   appearance: .darkAqua)
        render.settle(30)
        renders.append(render)
        return render
    }

    /// Both pop-ups, the switch and both palettes have real frames to read.
    /// Their right edges must agree to the point.
    ///
    /// **Which five, not how many.** A count alone passes a popover that has
    /// lost a mode pop-up and grown a ring somewhere else, so the five are
    /// checked in the order they stand in: two questions, the switch, two
    /// palettes. Not by width — a pop-up's ring sits at the control's own frame
    /// (152 pt here), not at the 156 the card gives it, so a width test would be
    /// asserting what AppKit charges for a bezel.
    func testEveryControlEndsOnTheSameRightEdge() {
        let render = mount()
        let down = controls(render.host)
            .map { (frame: $0.convert($0.bounds, to: render.host), isSwitch: $0 is NSSwitch) }
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(down.map(\.isSwitch), [false, false, true, false, false],
                       "expected two mode pop-ups, the switch, then two palettes; saw "
                       + "\(down.map { $0.isSwitch ? "switch" : "pop-up" })")
        let edges = down.map(\.frame.maxX)
        let spread = (edges.max() ?? 0) - (edges.min() ?? 0)
        XCTAssertLessThanOrEqual(spread, 1.0,
                                 "controls end \(spread) pt apart: \(edges.sorted())")
    }

    /// Two pictures, not six: the two questions each own one, and nothing
    /// repeats.
    func testThePopoverHoldsTwoPreviews() {
        let count = previewCount(mount().host)
        XCTAssertEqual(count, 2,
                       "the popover draws \(count) notice preview(s) — if that is 0, read "
                       + "`previewCount` first: the instrument has stopped matching, which is "
                       + "not the same finding as a picture having gone")
    }

    /// The height this shape was chosen for. A ratchet, not a target: it fails
    /// if the popover grows back towards the 483 pt it replaced.
    func testThePopoverStaysUnderItsCeiling() {
        let height = mount().fittingHeight
        XCTAssertLessThanOrEqual(height, 380, "the notices popover grew to \(height) pt")
    }

    private func controls(_ view: NSView) -> [NSView] {
        view.everyView.filter { $0.appKitClassName == "_FocusRingView" || $0 is NSSwitch }
    }

    /// A preview is a wallpaper drawn straight into a layer — it backs no view —
    /// so it is counted where it exists: a layer the size the card draws a
    /// notice preview at, clipped to the control corner.
    ///
    /// **Places, not layers.** One picture is drawn with more than one such
    /// layer — the clip and the hairline over it — so counting layers counts how
    /// the preview is built rather than how many there are. Their origins in the
    /// popover are what differs between two pictures and one.
    private func previewCount(_ view: NSView) -> Int {
        guard let root = view.layer else { return 0 }
        var places: Set<String> = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius == HelmRadius.ctl,
               layer.bounds.size == VPNConnectionCard.noticeThumbnail {
                places.insert("\(layer.convert(layer.bounds, to: root).origin)")
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return places.count
    }
}
