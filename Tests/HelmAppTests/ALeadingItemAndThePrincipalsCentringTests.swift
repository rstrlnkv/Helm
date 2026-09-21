import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Whether a real `.navigation` item changes the `.principal` item's
/// centred slot — established, not inherited.**
///
/// A previous headless stand proved that with nothing in the toolbar's leading
/// zone, AppKit reserves a symmetric slot for `.primaryAction` whose width
/// depends only on the `.principal` item's own width and the window's, and
/// centres the content inside it regardless of how many trailing buttons fill
/// it. That stand never mounted anything in `.navigation`, so it says nothing
/// about the shape the owner has since chosen — a real leading item, on every
/// page (`PageBarStyle.moduleName`). This file mounts one: `HelmIconPlate`
/// plus a name, the same construction `PageBarStyle.swift`'s `.moduleName` arm
/// builds, beside a fixed-width marker standing in for the `.principal` item
/// so its frame can be read without depending on `HelmToolbarSwitcher`'s own
/// layout timing.
///
/// # What was measured
///
/// A marker fixed at 272 × 36 pt as `.principal`, one or two plain buttons as
/// `.primaryAction`, with and without the leading item, at three widths (this
/// Mac, macOS 27, 2026-09-21):
///
/// - **1060 pt (the shipping default) and 1400 pt**: the marker's frame is
///   *identical to the pixel*, leading item present or not — (396, 708, 272,
///   36) at 1060, (566, 708, 272, 36) at 1400. Button count (one or two) made
///   no difference either, matching the earlier stand's own finding for the
///   trailing side. The centring math the earlier stand described is
///   unaffected by a leading item at these widths, because the leading item's
///   own width (about 98 pt — plate, spacing, "Homebrew" and the toolbar's own
///   leading padding) has room to sit clear of where the slot would centre
///   the marker anyway.
/// - **860 pt (`SettingsWindow.minSize`, the window's own floor)**: the two
///   readings diverge. With no leading item the marker sits at (296, 708,
///   272, 36) — leading gap 296, trailing gap 292, centred to within 4 pt,
///   the same near-symmetric slot as at every other width. With the leading
///   item mounted, the marker is pushed to (394, 708, 272, 36) — leading gap
///   394, trailing gap 194 — a 98 pt shift, matching the leading item's own
///   width: at the floor there is no longer room for both the leading item
///   and a truly centred slot, and AppKit keeps the leading item whole rather
///   than lay the `.principal` item over it.
///
/// So the answer this file exists to establish: **the leading item does not
/// change the centring math anywhere in the window's ordinary range** — the
/// shipping default included — **and only at the window's own floor does it
/// stop being centred at all**, becoming asymmetric in the trailing group's
/// favour rather than overlapping the module's name. `HomebrewSettingsPage`'s
/// own `switcherReserve` (250 pt) already carries slack for exactly this —
/// its own doc names "the page's name on the left" as part of what it
/// reserves, calibrated against real photographs that already had the header
/// mounted — so this file's finding is a confirmation of that calibration
/// with a number, not a correction to it.
@MainActor
final class ALeadingItemAndThePrincipalsCentringTests: XCTestCase {

    /// A fixed-size marker standing in for `.principal`'s own content, so its
    /// frame is a fact about the toolbar's layout and not about
    /// `HelmToolbarSwitcher`'s own metric-pinning timing
    /// (`TheToolbarSwitcherIsLaidOutOnceInTheBarsMetricTests`).
    private final class Marker: NSView {
        override var intrinsicContentSize: NSSize { NSSize(width: 272, height: 36) }
    }

    private struct MarkerView: NSViewRepresentable {
        func makeNSView(context: Context) -> Marker { Marker() }
        func updateNSView(_ nsView: Marker, context: Context) {}
    }

    private struct Page: View {
        let leading: Bool
        var body: some View {
            if leading {
                Color.clear
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack(spacing: HelmSpace.s5) {
                                HelmIconPlate(symbol: "shippingbox", tint: .green, size: 24)
                                Text("Homebrew")
                                    .font(.system(size: 16, weight: .semibold))
                                    .tracking(-0.2)
                                    .lineLimit(1)
                            }
                            .padding(.leading, HelmSpace.s5)
                        }
                        ToolbarItem(placement: .principal) { MarkerView() }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button("B0") { }
                        }
                    }
            } else {
                Color.clear
                    .toolbar {
                        ToolbarSpacer(.fixed, placement: .navigation)
                        ToolbarItem(placement: .principal) { MarkerView() }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button("B0") { }
                        }
                    }
            }
        }
    }

    private func mount(width: CGFloat, leading: Bool) -> NSWindow {
        let controller = NSHostingController(rootView: Page(leading: leading))
        controller.sceneBridgingOptions = [.toolbars]
        controller.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: 700))
        window.orderBack(nil)
        window.layoutIfNeeded()
        var found: Marker?
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, found == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            found = window.contentView?.superview?.everyView(ofType: Marker.self).first
        }
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return window
    }

    private func markerFrame(_ window: NSWindow) -> NSRect? {
        guard let marker = window.contentView?.superview?.everyView(ofType: Marker.self).first
        else { return nil }
        return marker.convert(marker.bounds, to: nil)
    }

    /// **The shipping default: identical, to the pixel, with or without the
    /// leading item.**
    func testAtTheShippingDefaultTheLeadingItemMovesNothing() throws {
        let without = mount(width: 1060, leading: false)
        let withLeading = mount(width: 1060, leading: true)
        let a = try XCTUnwrap(markerFrame(without), "no marker without a leading item")
        let b = try XCTUnwrap(markerFrame(withLeading), "no marker with a leading item")
        XCTAssertEqual(a, b, """
            the principal marker sits at \(a) with no leading item and \(b) with one, at 1060 pt \
            — the shipping default. The earlier stand's centring math no longer holds once a real \
            leading item is mounted, which changes what a switcher's width has to clear
            """)
        without.contentViewController = nil
        withLeading.contentViewController = nil
    }

    /// **At the window's own floor, the leading item displaces the slot
    /// rather than share it — by roughly its own width.**
    func testAtTheWindowsFloorTheLeadingItemDisplacesTheSlot() throws {
        let without = mount(width: 860, leading: false)
        let withLeading = mount(width: 860, leading: true)
        let a = try XCTUnwrap(markerFrame(without), "no marker without a leading item")
        let b = try XCTUnwrap(markerFrame(withLeading), "no marker with a leading item")
        XCTAssertEqual(a.minX, a.maxX.distance(to: 860), accuracy: 4, """
            with no leading item the marker is not centred at 860 pt (frame \(a) in an 860 pt \
            window) — the near-symmetric slot this file's own header describes has already moved
            """)
        XCTAssertGreaterThan(b.minX, a.minX + 50, """
            the marker moved only \(b.minX - a.minX) pt between no leading item and one, at the \
            window's own floor — this file expected a shift of roughly the leading item's own \
            width (about 98 pt), and a shift this small means the floor no longer squeezes the \
            two zones against each other the way it did when this was measured
            """)
        without.contentViewController = nil
        withLeading.contentViewController = nil
    }
}
