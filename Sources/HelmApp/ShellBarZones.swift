import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// **The dim shared by every piece of the name zone's own row, and by the
/// trailing status item beside it** — dimming together, as one unit,
/// applies across the name's view and the status's view now that the status
/// stands at the bar's trailing edge (2026-09-28), even though the two are
/// separate hosted views with nothing to composite together: each reads the
/// same four numbers (`helmNameZoneInactiveOpacity`) and is handed `appearsActive` from the one
/// `ShellPageBar.Snapshot`, so they move on exactly the same call.
@MainActor func helmNameZoneInactiveOpacity(dark: Bool, titlebarIsTransparent: Bool) -> Double {
    switch (dark, titlebarIsTransparent) {
    case (true, true): NameZoneView.inactiveOpacityDark
    case (false, true): NameZoneView.inactiveOpacityLight
    case (true, false): NameZoneView.inactiveOpacityOpaqueDark
    case (false, false): NameZoneView.inactiveOpacityOpaqueLight
    }
}

extension HelmToolbarActionsCapsule.InactiveInk {
    /// The numbers a flat capsule dims by in an inactive window: the name zone's, for the title bar the
    /// window wears. `ShellBarActions` and `SettingsToolbar` hand the capsule these.
    @MainActor static func nameZone(titlebarIsTransparent: Bool) -> Self {
        Self(dark: helmNameZoneInactiveOpacity(dark: true, titlebarIsTransparent: titlebarIsTransparent),
             light: helmNameZoneInactiveOpacity(dark: false, titlebarIsTransparent: titlebarIsTransparent))
    }
}

/// The name zone's own view: the module's plate and its name, the way
/// `PageBarStyle`'s `.moduleName` arm drew them before the bridge — reused
/// here rather than redrawn, to the letter of size and spacing. **The status
/// word or badge that used to sit
/// beside the name here draws in `StatusZoneView` instead**, at the bar's
/// trailing edge (the owner, 2026-09-28: «Давай вернем его в правую часть») —
/// this view no longer knows a module has one.
struct NameZoneView: View {
    let symbol: String
    let tint: Color
    let title: String
    /// False draws the name alone (`PageBarStyle.windowTitle`).
    var showsIcon = true
    let iconStyle: SidebarStyle
    /// **The same `isKeyWindow || isMainWindow` signal the actions capsule
    /// reads** (`SettingsToolbar.windowAppearsActive`'s own header has the
    /// reading), not `\.controlActiveState`: this view is hosted by the bar
    /// as the capsule is, outside the pane's view tree, and that
    /// environment key is not trusted here, for the capsule's reason
    /// (`HelmToolbarActionsCapsule`'s own header). `appearsActive` costs no
    /// rebuild the capsule's own glass needs — every ink below is a plain
    /// SwiftUI value read at draw time, not Liquid Glass, so reassigning this
    /// view's `rootView` (`ShellPageBar.draw`) is enough to move it.
    let appearsActive: Bool
    /// Which title bar the zone sits in — `window.titlebarAppearsTransparent`,
    /// which the band decision sets (`HelmBandChoice.titlebarAppearsTransparent`).
    /// AppKit dims its own title by a different amount under each, so the
    /// zone does too.
    let titlebarIsTransparent: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// **Dark 222→92, Light 37→177 — AppKit's own `.windowTitle` layout,
    /// measured against this same toolbar row under macOS 27's transparent
    /// title bar**: a window's title text over
    /// this row's own flat, inactive chrome (bg 37 Dark, 247 Light) lands on
    /// that target from the zone's own full ink (222 Dark, 38 Light) at the
    /// opacity `bg·(1−x) + ink·x = target` solves for — the same algebra
    /// `HelmToolbarActionsCapsule.inactiveGlyphOpacity…` uses for the
    /// capsule's own glyph, kept as its own pair of constants for the same
    /// reason that one is two and not one: the two appearances do not agree.
    /// **The plate dims by the same amount as the title, as one unit.**
    /// AppKit draws a title as a single readable line and offers no separate
    /// dimming for an icon beside it — there is no distinct AppKit reading to
    /// give the plate and the title of their own, and picking one anyway
    /// would be a difference this zone's own model (a module's name, standing
    /// in for the window's title) does not have. One `.opacity()` on the
    /// whole row is that decision. `StatusZoneView` dims by the same two
    /// numbers, in its own `.opacity()`, so the two read as one row even
    /// though nothing composites them together — its own header.
    static let inactiveOpacityDark: Double = 0.30    // (92−37)/(222−37) ≈ 0.2973
    static let inactiveOpacityLight: Double = 0.33   // (247−177)/(247−38) ≈ 0.3349
    /// **The same two under the opaque title bar — macOS 26's, by the band
    /// decision — and AppKit 27.2's answer to that decision, not macOS 26's.**
    /// Read on this Mac (27.2, engineer, 2026-09-27) under the title bar
    /// `HelmBandChoice.onMacOS(26)` sets, off AppKit's own title, as the share
    /// of its lit ink the title keeps inactive (S3 and S5 alike, through its
    /// own `draw(_:)`): Light
    /// 0.399, Dark 0.279 — against 0.329 and 0.296 under the transparent
    /// title bar in the same run, which the pair above answers. Whether
    /// macOS 26 itself dims its title by the same amount is for the owner's
    /// 26 virtual machine to confirm.
    static let inactiveOpacityOpaqueDark: Double = 0.28
    static let inactiveOpacityOpaqueLight: Double = 0.40

    private var inactiveOpacity: Double {
        helmNameZoneInactiveOpacity(dark: colorScheme == .dark, titlebarIsTransparent: titlebarIsTransparent)
    }

    var body: some View {
        HStack(spacing: HelmSpace.s5) {
            if showsIcon { HelmIconPlate(symbol: symbol, tint: tint, size: 24) }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
        }
        .padding(.leading, HelmSpace.s5)
        // Hosted outside the pane's own view tree, so the style this reads
        // has to be handed in explicitly rather than inherited.
        .environment(\.helmModuleIconStyle, iconStyle)
        // Flattens the row to one layer before dimming it — without this,
        // `HelmIconPlate`'s own drop shadow keeps its *own* alpha under the
        // opacity above rather than being scaled down with the plate, so the
        // two partly-transparent layers can composite to a higher combined
        // alpha right at the plate's edge than either dims to alone (measured:
        // the row's peak alpha read 0.54/0.58 instead of the requested
        // 0.30/0.33 without this line).
        .compositingGroup()
        .opacity(appearsActive ? 1 : inactiveOpacity)
    }
}

/// **The status word or badge, at the bar's trailing
/// edge** — the owner, 2026-09-28: «Давай вернем его в правую часть». A
/// sibling of `NameZoneView` rather than a branch inside it, because the two
/// are separate hosted views (`ShellPageBar.drawIdentity`; in `SettingsToolbar`, separate `NSToolbarItem`s),
/// drawing the two shapes a status has always had — a badge for active,
/// quiet text for idle, nothing for a module with no notion of running — and
/// dimming by the same four numbers (`helmNameZoneInactiveOpacity`) so the
/// two read as one row even though nothing composites them together.
///
/// **The trailing inset is the top gap, not the capsule's 8 pt** — the owner,
/// 2026-09-29: «Бейдж "Активно" / "Не активно" слишком близко находится к
/// правому краю экрана. Отступ сверху и справа должны быть одинаковые».
/// `trailingInset(for:barHeight:)` answers it: the gap from the
/// window's top edge to the drawn top of the badge's fill (or of the quiet
/// word's ink) is what AppKit's vertical centring leaves in a bar
/// `barHeight` tall, and the same distance is put between the drawn right
/// edge and the window's. The actions capsule stands `ShellBarLayout.trailing`
/// from the bar's edge, 8 pt: it is 36 pt tall in a 52 pt bar, so its top gap
/// is that 8 already, and only this view is shorter than the bar by enough to
/// matter.
///
/// **A nil status is passed, and the body marks it hidden from accessibility** —
/// `SettingsToolbar` makes this view for the shared name-only bar's status
/// item (`makeStatusItem`) and re-roots it with the status of the page on
/// screen (`patchName`): nil wherever `pageIdentity()` has none, and then it
/// draws nothing. `ShellPageBar` mounts it only with a status.
/// `accessibilityHidden(status == nil)` is on what this body draws; nothing
/// in `SettingsToolbar` sets accessibility on the hosting view or on the
/// item, whose `label` is then empty.
struct StatusZoneView: View {
    let status: (word: String, active: Bool)?
    let appearsActive: Bool
    let titlebarIsTransparent: Bool
    /// Between the hosted view's own trailing edge and what it draws — see
    /// `trailingInset(for:barHeight:)`.
    let trailingInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var inactiveOpacity: Double {
        helmNameZoneInactiveOpacity(dark: colorScheme == .dark, titlebarIsTransparent: titlebarIsTransparent)
    }

    var body: some View {
        Group {
            if let status {
                if status.active {
                    HelmBadge(status.word, tint: HelmSignal.success)
                } else {
                    Text(status.word)
                        .font(.system(size: 11))
                        .foregroundStyle(HelmText.quiet)
                }
            }
        }
        .padding(.trailing, trailingInset)
        .compositingGroup()
        .opacity(appearsActive ? 1 : inactiveOpacity)
        .accessibilityHidden(status == nil)
    }
}

extension StatusZoneView {

    /// **The distance AppKit left between an `isBordered = false` last
    /// item's own box and the window's trailing edge**, kept as a number: the
    /// 8 pt of a bordered item less `HelmToolbarActionsCapsule.edgeMargin`.
    /// No row measures it now, and `ShellPageBar` passes its own margin
    /// (`ShellBarLayout.statusTrailing`) instead of this default.
    static let boxMargin: CGFloat = 8 - HelmToolbarActionsCapsule.edgeMargin

    /// Where the drawing lies inside its own box, in points from the box's
    /// top and from its trailing edge — read off one offscreen render of the
    /// content with no inset, since a word's ink is not its box (the badge's
    /// fill is the whole box; a quiet word's cap line sits some way under the
    /// box's top and its last letter a fraction short of its right edge, and
    /// both move with the language).
    private struct Ink { let boxHeight: CGFloat, top: CGFloat, trailing: CGFloat }

    /// `nil` where the render draws nothing (an empty status, or a view AppKit
    /// would not photograph): the caller then keeps `HelmToolbarActionsCapsule.edgeMargin`.
    ///
    /// **Measured the way the placed item is laid out and drawn** — inside a
    /// window of its own that is never shown, so `fittingSize` keeps the
    /// backing scale's half points (a window-less hosting view was read, by an
    /// earlier tester, rounding a 56.5 pt word up to 57, and the inset came
    /// out half a point short).
    private static func ink(of status: (word: String, active: Bool)) -> Ink? {
        let host = NSHostingView(rootView: StatusZoneView(status: status, appearsActive: true,
                                                          titlebarIsTransparent: true, trailingInset: 0))
        host.sizingOptions = [.intrinsicContentSize]
        let probe = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                             styleMask: .borderless, backing: .buffered, defer: true)
        probe.isReleasedWhenClosed = false
        probe.contentView = host
        let size = host.fittingSize
        probe.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard size.width > 0, size.height > 0,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        let scale = CGFloat(rep.pixelsWide) / size.width
        var top = Int.max, right = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where Int(data[y * rep.bytesPerRow + x * 4 + alphaOffset]) > 12 {
                top = min(top, y)
                right = max(right, x)
            }
        }
        guard right >= 0 else { return nil }
        return Ink(boxHeight: size.height, top: CGFloat(top) / scale,
                   trailing: size.width - CGFloat(right + 1) / scale)
    }

    /// **The inset that puts the drawn right edge as far from the window's
    /// right edge as the drawn top is from its top.** The top gap is what
    /// AppKit's centring leaves: `(barHeight - box) / 2` above the box, plus
    /// the ink's own offset inside it (`Ink.top`); `barHeight` is the height
    /// of the bar the box is centred in: the window frame less its content
    /// layout rect for the toolbar (`SettingsToolbar.barHeight`),
    /// `ShellBarLayout.height` for the shell's bar. The right gap is
    /// `boxMargin` (AppKit's own margin), this inset and the ink's own
    /// trailing bearing, so the inset is the top gap less the other two. A host that sits flush against its bar's edge, with no AppKit margin
    /// between, passes `boxMargin: 0`.
    ///
    /// A not-a-number bar height (no window yet reads as none at all) and an
    /// unreadable render both keep `HelmToolbarActionsCapsule.edgeMargin`,
    /// the inset this item had before it followed the top; a result outside
    /// `0…barHeight` is clamped, a not-a-number to 0 — no inset is the
    /// nearer of the two wrong answers, an inset that eats the bar is not.
    static func trailingInset(for status: (word: String, active: Bool)?, barHeight: CGFloat?,
                              boxMargin: CGFloat = StatusZoneView.boxMargin) -> CGFloat {
        guard let status, let barHeight, barHeight.isFinite, barHeight > 0,
              let ink = ink(of: status) else { return HelmToolbarActionsCapsule.edgeMargin }
        let topGap = (barHeight - ink.boxHeight) / 2 + ink.top
        return (topGap - boxMargin - ink.trailing).clamped(to: 0...barHeight, whenNotANumber: 0)
    }
}
