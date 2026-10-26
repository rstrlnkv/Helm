import AppKit
import SwiftUI
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// **A page mounted with a real, attached `SettingsToolbar`** — the fixture of
/// the families that read the `NSToolbar` itself: its items, their order and
/// their frames.
///
/// Before the SwiftUI-AppKit bridge was replaced by `SettingsToolbar`
/// (`SettingsToolbar.swift`'s own header), `MountedRender`'s window picked up
/// a search field and a segmented control from `sceneBridgingOptions` with no
/// help from anything in `Tests/`. `SettingsToolbar` is `HelmApp`-only —
/// `HelmTestSupport` may reach `HelmRuntime` and `HelmUI` and nothing else
/// (`Package.swift`'s own "support may reach the shared plumbing, nothing may
/// reach support") — so a module's own `UITests` target has no way to build
/// one; only `HelmAppTests`, which already depends on `HelmApp` directly, can.
/// That is why the families that use it live here rather than in a module's
/// `UITests`, per `CLAUDE.md`'s "app-layer checks in
/// `Tests/HelmAppTests`" and ARCHITECTURE.md § Targets, where the host does take
/// a test target.
///
/// `selection` is set before the toolbar is even constructed — `SettingsToolbar`
/// refreshes from `model.selection` the moment its `window` is assigned
/// (`didSet`) — so the very first `refresh()` already reads the page this
/// fixture was built for; a caller settles (`settle(_:)`) before it reads what
/// the page declared.
@MainActor
struct LivePageInTheToolbarFixture {
    let mount: MountedRender
    let toolbar: SettingsToolbar
    let model: SettingsModel
    let channel: HelmWindowToolbarChannel

    init<V: View>(_ view: V, selection: SettingsSelection, width: CGFloat, height: CGFloat,
                 appearance: NSAppearance.Name = .aqua) {
        let channel = HelmWindowToolbarChannel()
        let model = SettingsModel(host: ModuleHost.shared)
        model.selection = selection
        let mount = MountedRender(view, width: width, height: height,
                                  appearance: appearance, channel: channel)
        let toolbar = SettingsToolbar(model: model, channel: channel)
        toolbar.window = mount.window
        self.mount = mount
        self.toolbar = toolbar
        self.model = model
        self.channel = channel
    }

    /// Settles the mount (`MountedRender.settle`), `turns` turns.
    func settle(_ turns: Int = 25) {
        mount.settle(turns)
    }

    func drop() {
        mount.drop()
    }
}

extension LivePageInTheToolbarFixture {

    /// The field of the search item on the window's toolbar (`MountedRender.toolbarSearchField`); nil when
    /// the fixture's window has no toolbar or the toolbar lists no search item.
    var searchField: NSSearchField? {
        mount.toolbarSearchField
    }
}
