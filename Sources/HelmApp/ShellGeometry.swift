import CoreGraphics
import HelmRuntime

/// **The arithmetic of the window's shell, as numbers in and numbers out: no
/// view, no window.** Everything is in the content's top-left coordinates,
/// and nothing here reads or holds state, so every function can be read from
/// any thread.
///
/// Three things are defined here. The *card* is the opaque page that sits
/// `inset` inside the window on its top, bottom and trailing sides, and starts
/// where the sidebar ends. The *rail* is the sidebar folded to `railWidth`. The
/// *capsule* is the pill in the rail that stands in for the window's three
/// buttons: closed it is a small pill, open it surrounds the buttons where
/// Helm holds them, and its *hover zone* is the area in which the pointer keeps
/// it open.
///
/// **The window's corner radius is not held here.** `cardRadius(windowRadius:)`
/// takes it as a parameter, so the card stays concentric with the corner it is
/// handed: on macOS 27 the token `HelmRadius.window`, on 26 what `WindowCorner` read.
///
/// `inset` is the owner's fixed gap. `railWidth`, `defaultSidebarWidth`,
/// `capsuleSize`, `capsuleShift`, `capsulePad` and `hoverMargin`
/// are the owner's numbers too, tuned by eye on a running window, not measured.
enum ShellGeometry {

    /// The gap between the window's edge and the card on the three sides the
    /// card does not share with the sidebar.
    nonisolated static let inset: CGFloat = 4

    /// The sidebar's width when it is folded to the rail.
    nonisolated static let railWidth: CGFloat = 56

    /// The width the sidebar has when it is expanded; nothing in the window drags it.
    nonisolated static let defaultSidebarWidth: CGFloat = 200

    /// The closed capsule's size.
    nonisolated static let capsuleSize = CGSize(width: 40, height: 18)

    /// How far right of the rail's centre the closed capsule sits.
    nonisolated static let capsuleShift: CGFloat = 2

    /// How much the open capsule extends past the buttons, per side:
    /// width sideways, height above and below.
    nonisolated static let capsulePad = CGSize(width: 9, height: 6)

    /// How far the hover zone reaches past the open capsule, right and down.
    nonisolated static let hoverMargin: CGFloat = 6

    /// How far below where AppKit puts them the window's three buttons stand.
    nonisolated static let buttonDrop: CGFloat = 6

    /// How far right of where AppKit puts them the window's three buttons stand when the sidebar is expanded.
    nonisolated static let buttonShift: CGFloat = 6

    /// How far right and down of where they stand without a toolbar AppKit puts the window's three buttons once the
    /// window wears one (`SettingsToolbar`): measured, 19 against 9 across and as far down. Helm holds the buttons at
    /// the same place under both looks (`ShellWindowButtons.placed`).
    nonisolated static let toolbarShift = CGSize(width: 10, height: 10)

    /// The title bar's band without a toolbar, which the sidebar's content stands below (measured: 32 against 66 with
    /// the toolbar, `SettingsToolbar`): the same under both looks.
    nonisolated static let titleBand: CGFloat = 32

    /// Whether a sidebar of `sidebarWidth` is the rail. Not-a-number is not the
    /// rail, so a bad number never folds the buttons away.
    nonisolated static func isRail(sidebarWidth: CGFloat) -> Bool {
        sidebarWidth <= railWidth
    }

    // MARK: - the card

    /// **The card inside a window of `size` whose sidebar is `sidebarWidth`
    /// wide.** Its x is `sidebarWidth`, its y is `inset`, and it ends `inset`
    /// short of the window's trailing and bottom edges.
    ///
    /// A window too small for the card gives a size of zero, never a negative
    /// one, and the size is always finite: not-a-number reads as zero, and a
    /// result that overflows (a huge window less a huge negative width) is held
    /// at the largest finite number. A sidebar width that is not finite reads as
    /// 0 — for x as well as for the width the card loses to it — because a
    /// frame whose origin is not a number cannot be placed; a finite width is
    /// used as given, also past the window's edge or below zero, since the width
    /// is only ever between `railWidth` and `defaultSidebarWidth` and
    /// bending it here would put x and the sidebar in two places.
    nonisolated static func cardFrame(in size: CGSize, sidebarWidth: CGFloat) -> CGRect {
        let sidebar = sidebarWidth.isFinite ? sidebarWidth : 0
        let widest = CGFloat.greatestFiniteMagnitude
        let width = (size.width - sidebar - inset).clamped(to: 0...widest, whenNotANumber: 0)
        let height = (size.height - 2 * inset).clamped(to: 0...widest, whenNotANumber: 0)
        return CGRect(x: sidebar, y: inset, width: width, height: height)
    }

    /// **The card's corner radius for a window whose corner is `windowRadius`:**
    /// the window's less `inset`, so the two corners share a centre. Never
    /// below zero (a corner smaller than the gap is square); not-a-number or
    /// infinite reads 0, a card drawn square, since neither is a corner.
    nonisolated static func cardRadius(windowRadius: CGFloat) -> CGFloat {
        windowRadius.isFinite ? max(windowRadius - inset, 0) : 0
    }

    // MARK: - the window's buttons

    /// **How far the buttons stand from where AppKit puts them (`home`, the
    /// union of the three), right and down.** Expanded: `buttonShift` and
    /// `buttonDrop`. In the rail: down by `buttonDrop` as well, and right so that
    /// the buttons' left edge is the closed capsule's plus `capsulePad.width`,
    /// the edge the open capsule draws them from, so they open out of the
    /// capsule on the same row.
    nonisolated static func buttonsOffset(home: CGRect, rail: Bool) -> CGSize {
        guard rail else { return CGSize(width: buttonShift, height: buttonDrop) }
        return CGSize(width: capsuleClosedFrame(buttons: home).minX + capsulePad.width - home.minX,
                      height: buttonDrop)
    }

    // MARK: - the capsule

    /// The capsule's frame closed: `capsuleSize`, at the rail's centre moved
    /// right by `capsuleShift`, centred on the row of `buttons`. `ShellWindowButtons.placed(home:rail:)` hands it the
    /// buttons where they stand, the drop already in them; `buttonsOffset` hands it the home and reads only
    /// the x, which does not depend on the row.
    nonisolated static func capsuleClosedFrame(buttons: CGRect) -> CGRect {
        let row = placed(buttons)
        return CGRect(x: (railWidth - capsuleSize.width) / 2 + capsuleShift,
                      y: row.midY - capsuleSize.height / 2,
                      width: capsuleSize.width,
                      height: capsuleSize.height)
    }

    /// The capsule's frame open: `buttons` grown by `capsulePad` on every side,
    /// around the buttons wherever they stand.
    nonisolated static func capsuleOpenFrame(buttons: CGRect) -> CGRect {
        placed(buttons).insetBy(dx: -capsulePad.width, dy: -capsulePad.height)
    }

    /// **The area in which the pointer keeps the capsule open:** from the
    /// content's corner past the open frame by `hoverMargin` right and down,
    /// and at least `railWidth` wide. It holds the closed frame and the open
    /// one only while the buttons' minX is at least `capsulePad.width`, their
    /// minY at least `capsulePad.height` and their midY at least half of
    /// `capsuleSize.height`; buttons nearer the corner than that, or above it,
    /// leave part of a frame outside the zone.
    nonisolated static func capsuleHoverZone(buttons: CGRect) -> CGRect {
        let open = capsuleOpenFrame(buttons: buttons)
        return CGRect(x: 0, y: 0,
                      width: max(open.maxX + hoverMargin, railWidth),
                      height: open.maxY + hoverMargin)
    }

    /// `buttons` as the capsule reads it. A rect that is null, infinite, or has
    /// a coordinate or an edge that is not finite reads as the empty rect at the
    /// content's corner, so the frames built from it stay finite instead of
    /// carrying a not-a-number into a layout.
    private nonisolated static func placed(_ buttons: CGRect) -> CGRect {
        let edges = buttons.standardized
        let known = !buttons.isNull && !buttons.isInfinite
            && [buttons.origin.x, buttons.origin.y, buttons.size.width, buttons.size.height,
                edges.maxX, edges.maxY].allSatisfy(\.isFinite)
        return known ? buttons : .zero
    }
}
