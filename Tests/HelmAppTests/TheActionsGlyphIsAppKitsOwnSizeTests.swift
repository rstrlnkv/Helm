import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The owner's report (2026-09-27): "the glyph on the Refresh button is very
/// small."** Every glyph in `HelmToolbarActionsCapsule` is a SwiftUI `Label`
/// hosted in the item's own `NSHostingView`, and with no font of its own it
/// took that view's default — body type — where AppKit draws the symbol of a
/// live toolbar button, a bordered item with a target and an action as
/// Refresh is, larger.
///
/// **The reference is AppKit's own drawing, read fresh every run, never a
/// number this file remembers.** A bare `NSToolbar` holding one bordered
/// `NSToolbarItem` with a target and an action whose image is the same
/// symbol — the shape `BareToolbarEdgeProbeDelegate` already uses for the
/// edge margin — and the ink box of the `NSToolbarButton` AppKit draws for
/// it, against the ink box of the capsule's own glyph on a real, attached
/// `SettingsToolbar`.
///
/// **It has to be a live button.** An item with no action is drawn through
/// `NSToolbarImageView` instead, greyed as disabled and larger; this file
/// measured against that one until 2026-09-28 and held the glyph at 20 pt,
/// a size no pressable item on the bar is drawn at.
///
/// **Red from both sides** (2026-09-28, `bash Scripts/test.sh --filter
/// TheActionsGlyphIsAppKitsOwnSizeTests`, Light and Dark alike): the glyph
/// still at that 20 pt reads 17.5 × 21.0 pt of ink for Refresh against the
/// live button's 14.5 × 17.5, and the glyph with its font and image-scale
/// lines taken out reads 11.5 × 13.5 against the same — twelve box failures
/// each, and six weight failures each once the weight below was added.
///
/// **The weight, not only the box.** A box is blind to the stroke: at 13 pt
/// large, `.regular` draws Refresh the same 14.5 × 17.5 as `.medium` and
/// passed the box assertions alone (2026-09-28). So each glyph's ink is also
/// weighed — every alpha in its slot summed and divided by the strongest,
/// which reads the stroke area whatever alpha AppKit happens to draw at —
/// against the live button's. Read the same day, Light and Dark alike:
/// `.medium` 0.999 to 1.001 of AppKit's weight for all three symbols,
/// `.regular` 0.81 to 0.84, `.semibold` 1.12 to 1.15 — each of those two a
/// run with six weight failures and no box failure.
///
/// **Every kind that draws through the shared glyph**, button, toggle and
/// menu, each against AppKit's own drawing of the same symbol; `.segmented` is
/// AppKit's own `NSSegmentedControl` and draws its glyphs itself.
@MainActor
final class TheActionsGlyphIsAppKitsOwnSizeTests: XCTestCase {

    /// One glyph's ink: where it lies and how much stroke it holds — `ink(_:slot:)`.
    private struct Ink { let box: NSRect; let weight: CGFloat }

    /// The bounding box of every pixel `view` draws inside `slot` (its own
    /// points, full height) at more than a third of the strongest alpha found
    /// there, in its own points. Relative rather than absolute because a
    /// fixed cut measured how the glyph was drawn as well as its shape: at a
    /// fixed 0.25, AppKit's action-less toolbar Refresh read 16.5 × 20.0 while
    /// a plain `NSImageView` showing the same symbol at the same 20 pt
    /// configuration — a bitmap matching AppKit's pixel for pixel — read
    /// 17.0 × 21.0 (2026-09-27). Glass does not composite in a test process
    /// (`TheCapsuleDrawsWhatAppKitsPlatterDrawsTests`' own header), so what is
    /// left in the bitmap is the glyph itself — for AppKit's button and for
    /// ours alike.
    ///
    /// `weight` is every alpha in the slot summed and divided by the
    /// strongest, in square points: the stroke's area, read the same way
    /// whether the glyph is drawn at full ink or dimmed — AppKit's button in
    /// this never-key window draws at about a quarter, ours at full.
    private static func ink(_ view: NSView, slot: ClosedRange<CGFloat>? = nil) -> Ink? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
        let range = slot ?? 0...view.bounds.width
        let from = max(0, Int((range.lowerBound * scale).rounded(.down)))
        let to = min(rep.pixelsWide, Int((range.upperBound * scale).rounded(.up)))
        guard from < to else { return nil }
        var strongest: CGFloat = 0
        var total: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in from..<to {
                if let alpha = rep.colorAt(x: x, y: y)?.alphaComponent {
                    strongest = max(strongest, alpha)
                    total += alpha
                }
            }
        }
        guard strongest > 0 else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in from..<to {
                guard let alpha = rep.colorAt(x: x, y: y)?.alphaComponent, alpha > strongest / 3 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let box = NSRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                         width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        return Ink(box: box, weight: total / strongest / (scale * scale))
    }

    private static func first(_ className: String, under view: NSView) -> NSView? {
        if String(describing: type(of: view)) == className { return view }
        for sub in view.subviews {
            if let found = first(className, under: sub) { return found }
        }
        return nil
    }

    /// AppKit's own ink for `symbol` on a live bordered toolbar item — one
    /// with a target and an action, as Refresh is, which AppKit draws as an
    /// `NSToolbarButton` — in a bare window of the same width and appearance.
    private func appKitsInk(_ symbol: String, appearance: NSAppearance.Name) throws -> Ink {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let delegate = BorderedImageItemDelegate(symbol: symbol)
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("glyph.reference.\(appearance.rawValue)"))
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        for _ in 0..<10 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        defer { withExtendedLifetime(delegate) { window.toolbar = nil } }
        let frame = try XCTUnwrap(window.contentView?.superview, "no theme frame")
        // Found by class name, the way `SettingsToolbar.windowTitleMaxX` finds
        // AppKit's own title: read only, never messaged beyond `NSView`'s
        // public surface. `NSToolbarButton` and not `NSToolbarImageView`:
        // the second is what AppKit draws an item with no action through,
        // greyed as disabled and larger, and a reference found that way holds
        // the capsule to a drawing no pressable item on the bar ever gets.
        let drawn = try XCTUnwrap(Self.first("NSToolbarButton", under: frame),
                                  "AppKit no longer draws a live bordered item through NSToolbarButton — re-probe")
        return try XCTUnwrap(Self.ink(drawn), "AppKit's own toolbar image drew no ink")
    }

    /// The three kinds that draw through `HelmToolbarActionsCapsule`'s shared
    /// glyph, declared through the real channel so `SettingsToolbar
    /// .actionEntries(for:)` builds them — one symbol each, so each slot is
    /// compared against AppKit's own drawing of that same symbol.
    private static let declared: [(symbol: String, action: HelmToolbarAction)] = [
        ("arrow.clockwise", HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}),
        ("text.alignleft", HelmToolbarAction(id: "mode", title: "Plain text", symbol: "text.alignleft",
                                             isOn: false) {}),
        ("line.3.horizontal.decrease.circle",
         HelmToolbarAction(id: "kinds", title: "Filter", symbol: "line.3.horizontal.decrease.circle", menu: [
             HelmToolbarMenuItem(id: "a", title: "A", isOn: true) {},
         ])),
    ]

    /// Our ink per declared slot, in the capsule's own points: the entries sit
    /// left to right at `HelmToolbarActionsCapsule.side` apiece.
    private func oursInk(appearance: NSAppearance.Name) throws -> [Ink] {
        let fx = LivePageToolbarFixture(Color.clear, selection: .module("test.glyphs"),
                                        width: 1060, height: 700, appearance: appearance)
        defer { fx.drop() }
        fx.channel.declare(HelmPageToolbarContent(actions: Self.declared.map(\.action)),
                           token: "test.glyphs", generation: fx.channel.nextGeneration())
        fx.settle(30)
        let toolbar = try XCTUnwrap(fx.mount.window?.toolbar, "no toolbar")
        let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "helm.actions" },
                                 "no helm.actions item")
        let capsule = try XCTUnwrap(item.view as? NSHostingView<HelmToolbarActionsCapsule>, "no capsule")
        XCTAssertEqual(capsule.rootView.model.visibleIDs, Self.declared.map(\.action.id),
                       "not every declared kind is on the capsule — a slot would read a neighbour's glyph")
        let side = HelmToolbarActionsCapsule.side
        return try Self.declared.indices.map { index in
            let slot = CGFloat(index) * side...CGFloat(index + 1) * side
            return try XCTUnwrap(Self.ink(capsule, slot: slot),
                                 "\(Self.declared[index].action.id) drew no ink in its slot")
        }
    }

    func testEveryCapsuleGlyphDrawsAtTheSizeAndWeightOfALiveToolbarButtonsGlyph() throws {
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            let ours = try oursInk(appearance: appearance)
            for (index, entry) in Self.declared.enumerated() {
                let reference = try appKitsInk(entry.symbol, appearance: appearance)
                let id = entry.action.id
                let mine = ours[index]
                XCTAssertEqual(mine.box.width, reference.box.width, accuracy: 0.5, """
                    \(appearance.rawValue): \(id)'s ink is \(mine.box.width) pt wide, AppKit's own \
                    live toolbar button draws \(entry.symbol) \(reference.box.width) pt wide \
                    (ours \(mine.box), AppKit's \(reference.box))
                    """)
                XCTAssertEqual(mine.box.height, reference.box.height, accuracy: 0.5, """
                    \(appearance.rawValue): \(id)'s ink is \(mine.box.height) pt tall, AppKit's own \
                    live toolbar button draws \(entry.symbol) \(reference.box.height) pt tall \
                    (ours \(mine.box), AppKit's \(reference.box))
                    """)
                // Half-way to the nearest wrong weight on either side — see
                // this file's header for the readings.
                XCTAssertEqual(mine.weight / reference.weight, 1, accuracy: 0.05, """
                    \(appearance.rawValue): \(id)'s stroke weighs \(mine.weight / reference.weight) of \
                    the one AppKit's own live toolbar button draws for \(entry.symbol) \
                    (ours \(mine.weight) pt², AppKit's \(reference.weight) pt²) — another font \
                    weight, or another size the box assertions above name
                    """)
            }
        }
    }
}

/// One bordered image item with a target and an action, nothing else —
/// `BareToolbarEdgeProbeDelegate`'s shape with an image instead of a view, so
/// AppKit draws the glyph itself, and draws it the way it draws a button a
/// person can press. The action is the point: without it AppKit draws the
/// same item through `NSToolbarImageView`, greyed as disabled and larger.
@MainActor
private final class BorderedImageItemDelegate: NSObject, NSToolbarDelegate {
    static let itemID = NSToolbarItem.Identifier("glyph.reference")
    let symbol: String
    init(symbol: String) { self.symbol = symbol }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        item.label = symbol
        item.isBordered = true
        item.target = self
        item.action = #selector(press(_:))
        return item
    }

    @objc private func press(_ sender: Any?) {}

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.itemID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}
