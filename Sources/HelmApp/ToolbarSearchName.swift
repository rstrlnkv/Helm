import AppKit
import HelmUI

/// **The name on the search control macOS builds for us.**
///
/// A page asks for search with `helmSearchable`, the pane's toolbar bridge
/// carries the declaration into the window, and AppKit builds an
/// `NSSearchToolbarItem` around a real `NSSearchField`. That field has no name:
/// measured on macOS 27 (2026-09-20), `accessibilityLabel()` and
/// `accessibilityTitle()` are both nil on the mounted control, empty and typed
/// into alike, and a SwiftUI `.accessibilityLabel` on the searchable view never
/// reaches it — the field is not in that view's tree. Only the *collapsed*
/// magnifier is named, by the system. So the name is set from this side, where
/// the field actually is, and it is `HelmA11y.searchField`: the same word the
/// page's own field carried before the control moved.
///
/// **A one-off naming at window setup would be worth nothing**, and that is the
/// whole reason this is an object rather than three lines in
/// `SettingsWindow.init`. Two measurements say so, both taken against a window
/// carrying the same bridge the settings window has:
///
/// - the item is not there at window-setup time — the window has no toolbar at
///   all until the bridge publishes the page's, which it does one turn of the
///   main queue later;
/// - and it is **a new object every time the page changes**. Switching away
///   from a page that searches and back gave three different `NSSearchField`
///   instances over two round trips, each one nameless, and the label set on
///   the first went with it.
///
/// **So there are two channels, because neither covers the other's case.**
///
/// - `NSToolbar.willAddItemNotification` fires when an item joins a toolbar
///   that already exists — twice per round trip away from a searching page and
///   back, once per item, with the item in `userInfo`. A name set there held
///   through both round trips and through typing into the field. This is the
///   channel for what changes *within* a page: Homebrew's segment moving to
///   Поиск adds the item with no page change behind it.
/// - and it does **not** fire for the first toolbar, measured: a window built
///   with this bridge and watched from before its first run-loop turn saw zero
///   `willAddItem` notifications, and zero KVO notices on `NSToolbar.items` and
///   on `NSWindow.toolbar` as well — the toolbar arrives already populated.
///   What does see it is one hop of the main queue, which is the hop
///   `SettingsWindow` already takes for `settleDisplayMode` and for the same
///   reason. `nameWhatIsThere` is that half, and it runs on every page change
///   as well as at the start, since a rebuilt bar is the same situation again.
///
/// The language change is a second channel for the same reason
/// `HelmSearchField.updateNSView` re-read the name rather than setting it once:
/// the app's language changes while it runs, and a name taken at the moment the
/// item was built would answer in whichever language the page was last rebuilt
/// in.
///
/// **This object also gives the control its focused width** — AppKit's own
/// leftover-room decision governs the resting width now, and nothing here
/// pins that any more; see `size(_:)` for the three orders this control has
/// had and why the third landed here rather than at the two call sites: both
/// are a fact about the bridged field, not about either page, and both need
/// the same two channels the name does.
@MainActor final class ToolbarSearchName: NSObject {

    /// Weak, and the only state here: this object is owned by the window it
    /// names for, and a strong pointer back would be the cycle that keeps a
    /// closed window alive.
    private weak var window: NSWindow?

    init(namingIn window: NSWindow) {
        self.window = window
        super.init()
        // `object: nil` rather than the window's toolbar: at the moment this is
        // built the window has no toolbar at all — the bridge makes it — so
        // there is nothing to register against yet. Which toolbar the item went
        // to is asked at delivery instead.
        NotificationCenter.default.addObserver(
            self, selector: #selector(toolbarWillAddItem(_:)),
            name: NSToolbar.willAddItemNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageChanged),
            name: .helmLanguageChanged, object: nil)
        // The first toolbar announces nothing, so it is read rather than waited
        // for — one hop, the same one `SettingsWindow.show` takes, by which
        // point the bridge has published the page's items.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.nameWhatIsThere() }
        }
    }

    deinit {
        // Nonisolated, so it is one of the few things a `deinit` on a
        // main-actor class may do — and the reason it is here is the rule about
        // an observer outliving what it points at rather than any route that is
        // known to run: the settings window is not released while the app runs.
        NotificationCenter.default.removeObserver(self)
    }

    /// AppKit's own key for the item in this notification's `userInfo`. Spelled
    /// rather than read off a constant because the framework exports none to
    /// Swift; measured against the delivered notification.
    private static let itemKey = "item"

    @objc private func toolbarWillAddItem(_ note: Notification) {
        guard let item = note.userInfo?[Self.itemKey] as? NSSearchToolbarItem else { return }
        // A toolbar that is not this window's is not this object's business.
        // Asked here and not at registration: see `init`.
        guard let toolbar = note.object as? NSToolbar, toolbar === window?.toolbar else { return }
        item.searchField.setAccessibilityLabel(HelmA11y.searchField)
        Self.size(item)
    }

    @objc private func languageChanged() { nameWhatIsThere() }

    /// Name every bridged search field the toolbar is holding right now.
    ///
    /// Internal rather than private: the language channel is one caller,
    /// `SettingsWindow.settleDisplayMode` — which already runs on the hop after
    /// every page change — is the second, and a test is the third. The
    /// alternative, a test that waits for an item to be added and reads the
    /// label off a notification, would be measuring the notification rather
    /// than the control.
    func nameWhatIsThere() {
        for item in window?.toolbar?.items ?? [] {
            guard let search = item as? NSSearchToolbarItem else { continue }
            search.searchField.setAccessibilityLabel(HelmA11y.searchField)
            Self.size(search)
        }
    }

    // MARK: - Width

    /// **The resting state is a field again, and it collapses to the
    /// magnifier only where the window is narrow — the owner's third order on
    /// this control (2026-09-21).** The first, "make it the magnifier",
    /// replaced a prompt-sized resting field (`max(160, naturalWidth(…))`
    /// pinned with a `.defaultHigh` width constraint) whose collapse the
    /// designer had swept 1100→860 pt in 4 pt steps and found unreachable:
    /// 162.0 pt at every one of 61 steps, because that sweep's fixture carried
    /// nothing in the toolbar's leading zone — a bare `ToolbarSpacer` — so
    /// there was nothing to leave the field short of room. Pinning *any*
    /// constant with a priority AppKit will actually hold turns out not to be
    /// the fix in either direction: measured against real pages (Homebrew,
    /// Uninstaller) with the module-name header mounted, a `.defaultHigh` **or**
    /// a mid-priority (500) constraint at 162, 200 or 220 pt held exactly that
    /// width from 1100 pt down to the window's own 860 pt floor
    /// (`SettingsWindow.minSize`) and never once collapsed — the toolbar sends
    /// an item it cannot shrink into overflow rather than compress it, so a
    /// pinned width is either always open or (below 160) always the
    /// magnifier, and nothing in between.
    ///
    /// **So nothing here pins a resting width at all.** `size(_:)` below only
    /// clears whatever width constraint might already be on the field and
    /// leaves it be — the same "AppKit decides it from the width the toolbar
    /// has left over" this control had before any of these three orders,
    /// which `HelmSearchable.swift`'s own doc already named as the mechanism.
    /// What makes that reachable now, where the very first sweep found it was
    /// not: the leading zone is no longer empty. `PageBarStyle.moduleName`
    /// puts the module's plate and name there on every page, and that is room
    /// the toolbar did not use to spend.
    ///
    /// **The numbers this paragraph used to give were a headless sweep's, and
    /// they were wrong by ninety points and more.** A designer's reading of
    /// the *rendered* window (real app, AX frames plus pixels, key window
    /// verified on every frame, each reading taken twice, 2026-09-21) found:
    ///
    /// - **Homebrew**: the magnifier at the 1060 pt shipping default; the
    ///   threshold sits between 1112 pt (collapsed) and 1120 pt (open,
    ///   162 pt field).
    /// - **Uninstaller**: never collapses, at any width from 1100 pt down to
    ///   the 860 pt window floor, where it still draws a 163.0 pt field.
    ///
    /// A headless sweep of both pages read Homebrew open at 1024 and a 198 pt
    /// field at 1060, and Uninstaller collapsing at 884–888 — the shape this
    /// paragraph reported before. Rebuilding that sweep's fixture with the
    /// window's real 214 pt sidebar mounted (`SettingsSplitViewController`,
    /// which the old fixture skipped entirely) did not close the gap; it
    /// moved *both* pages' thresholds further from the rendered numbers, in
    /// the same direction, regardless of which page's toolbar is lighter or
    /// heavier — which rules out a missing sidebar as the whole mechanism.
    /// What such a fixture cannot be shown to reproduce at all is Liquid
    /// Glass's own adaptive collapse, which is a compositing decision, and an
    /// offscreen window built with `orderBack(nil)` and never made key is not
    /// shown anywhere in this tree to composite glass — see
    /// `ASearchCollapsesOnlyWhereTheWindowIsSmallTests`'s own header for the
    /// measurement that found this. So the exact crossing is the rendered
    /// numbers above and nothing measured in a harness, headless or not.
    ///
    /// **What survives from a headless sweep, because it does not depend on
    /// glass compositing, is the direction: the leading item narrows the room
    /// left for the field, and for one of the two pages that is what makes
    /// the collapse reachable at all within the window's own range.** Without
    /// it, `ASearchCollapsesOnlyWhereTheWindowIsSmallTests` still finds
    /// Uninstaller's field open at every width its sweep reaches, 860 pt
    /// included — which is why `PageBarStyle`'s default is `moduleName` and
    /// not merely its shipping preference.
    ///
    /// The 160 pt floor itself is untouched and still AppKit's, not this
    /// file's: **below 160 pt AppKit draws the magnifier whatever the
    /// toolbar's own room is** — measured on this Mac (macOS 27, 2026-09-21)
    /// by forcing the field's width directly in a 900 pt window, far wider
    /// than the control could ever need: 159 pt drew collapsed and 160 pt
    /// drew open, on every width either side of that line
    /// (`TheSearchFieldRestsNarrowerAndWidensOnFocusTests`). That test still
    /// holds; what changed is only that nothing here fights AppKit down to
    /// that floor with a constraint of its own any more.
    ///
    /// Set as a fresh removal rather than a stored constraint kept and
    /// mutated: this fires on a language change and a page change alike, is
    /// cheap enough that repeating it is not a live hazard, and it defends
    /// against a stray width constraint surviving on a field AppKit reuses in
    /// place — measured nowhere to happen, but a field this code does not own
    /// the lifetime of is exactly the object-outliving-its-owner trap in the
    /// engineer's own notes under a different name.
    private static func size(_ item: NSSearchToolbarItem) {
        let field = item.searchField
        field.constraints
            .filter { $0.firstItem === field && $0.firstAttribute == .width }
            .forEach { $0.isActive = false }
        item.preferredWidthForSearchField = focusedWidth
    }

    /// **The focused width — fixed, and not a function of the prompt or the
    /// language at all.** What somebody types is not this interface's own
    /// words, so it is not translated and not measured against a translation;
    /// it needs room for the cancel button a placeholder reading never pays
    /// for — measured on "Search apps", 108 pt as a placeholder against 132 pt
    /// typed in, the 24 pt difference being exactly that button
    /// (`TheSearchFieldRestsNarrowerAndWidensOnFocusTests`). Sized here against
    /// "Microsoft Remote Desktop", a real 24-character application name
    /// standing in for a query somebody actually types, so the field widened
    /// on a click can show one rather than only the prompt it replaces.
    private static let focusedWidth: CGFloat = naturalWidth(typed: "Microsoft Remote Desktop")

    /// The width AppKit itself gives a search field sized for one string —
    /// typed content, with the cancel button that comes with it — read off a
    /// throwaway probe that is never mounted and never drawn, rather than
    /// approximated with a written constant.
    private static func naturalWidth(typed: String) -> CGFloat {
        let probe = NSSearchField()
        probe.stringValue = typed
        probe.sizeToFit()
        return probe.frame.width
    }
}
