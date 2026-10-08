import AppKit
import HelmUI
@testable import HelmApp

/// **A real `ShellPageBar` with its three real zones, put into a window somebody else built.**
///
/// The bar has no window of its own: whoever owns it writes its frame and its `place`, as the shell's
/// content view does for the real window. This does the same for a test window that only holds a page.
/// The bar's view is added next to the window's content view, in the window's frame view, so the page's
/// own ink readings (`host.cacheDisplay`) do not contain it, and a walk down from the frame view finds it.
///
/// The zones are the bar's private fields, so the ones built here are kept: a test that reads a zone
/// reads it from here. The bar's assembly below is a copy of the one in
/// `Sources/HelmApp/SettingsWindow.swift` (including `tabs.barMenu = bar.view.menu`), so new wiring there
/// drifts from here unless it is copied too. Nothing is pinned for the settings the bar reads when it is
/// built (`AppSettings.pageBarStyle`, `sidebarStyle`, `alwaysCollapseSearch`, `barAppearance`) nor for the
/// fifth its tabs zone reads (`AppSettings.toolbarSwitcherStyle`): a family that depends on one pins it
/// before building the bar (`PinnedBarSettings.pin(in:)`) and puts it back.
///
/// `layout()` has to be called after anything that moves the bar's frames; `MountedRender.settle` lays
/// out the page's host and nothing else.
@MainActor
struct MountedPageBar {
    let bar: ShellPageBar
    let tabs: ShellBarTabs
    let actions: ShellBarActions
    let search: ShellBarSearch
    let window: NSWindow?

    init(model: SettingsModel, channel: HelmWindowToolbarChannel, in window: NSWindow?,
         titlebarIsTransparent: Bool = true) {
        let tabs = ShellBarTabs(titlebarIsTransparent: titlebarIsTransparent)
        let actions = ShellBarActions(titlebarIsTransparent: titlebarIsTransparent)
        let search = ShellBarSearch(titlebarIsTransparent: titlebarIsTransparent)
        let bar = ShellPageBar(model: model, channel: channel, tabs: tabs, actions: actions,
                               search: search, titlebarIsTransparent: titlebarIsTransparent)
        tabs.barMenu = bar.view.menu
        window?.contentView?.superview?.addSubview(bar.view)
        self.bar = bar
        self.tabs = tabs
        self.actions = actions
        self.search = search
        self.window = window
        layout()
    }

    /// Sets the bar's frame and `place` from the window's content view, then lays the bar out.
    func layout() {
        if let content = window?.contentView {
            let c = content.frame
            bar.view.frame = NSRect(x: c.minX, y: c.maxY - ShellBarLayout.height,
                                    width: c.width, height: ShellBarLayout.height)
            bar.view.place = ShellPageBarView.Place(cardMinX: 0, windowWidth: c.width, buttons: .null)
        }
        bar.view.layoutSubtreeIfNeeded()
    }

    /// Takes the bar out of the window. A window whose content view is replaced keeps the bar in its
    /// frame view, so a fixture that is dropped calls this.
    func remove() {
        bar.view.removeFromSuperview()
    }
}
