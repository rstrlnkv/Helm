import AppKit
import SwiftUI
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// **A page mounted with a real, attached `SettingsToolbar` — the fixture
/// four Homebrew integration tests moved here for**, once their own mount
/// stopped putting anything in `window.toolbar` at all.
///
/// Before the SwiftUI-AppKit bridge was replaced by `SettingsToolbar`
/// (`SettingsToolbar.swift`'s own header), `MountedRender`'s window picked up
/// a search field and a segmented control from `sceneBridgingOptions` with no
/// help from anything in `Tests/`. `SettingsToolbar` is `HelmApp`-only —
/// `HelmTestSupport` may reach `HelmRuntime` and `HelmUI` and nothing else
/// (`Package.swift`'s own "support may reach the shared plumbing, nothing may
/// reach support") — so a module's own `UITests` target has no way to build
/// one; only `HelmAppTests`, which already depends on `HelmApp` directly, can.
/// That is why these tests live here now rather than in
/// `Tests/Modules/Homebrew/UITests`, per `CLAUDE.md`'s own "put a check for
/// the app layer in `Tests/HelmAppTests`, since the host does take a test
/// target and there is no reason to move code out of it to reach one."
///
/// `selection` is set before the toolbar is even constructed — `SettingsToolbar`
/// refreshes from `model.selection` the moment its `window` is assigned
/// (`didSet`) — so the very first `refresh()` already reads the page this
/// fixture was built for, with whatever content the mount's own `settle()`
/// call below has by then let the page declare.
@MainActor
struct LivePageToolbarFixture {
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

    /// Settles the mount and re-asserts the selection so a fixture reused
    /// across several `draw`-style calls in one test (`TheNarrowBandActsIn-
    /// EverySegmentTests`) reads the page's latest declare rather than
    /// whichever one was current when it was built.
    func settle(_ turns: Int = 25) {
        mount.settle(turns)
    }

    func drop() {
        mount.drop()
    }
}
