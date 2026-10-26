import AppKit
import SwiftUI
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// **A page mounted in a window that holds the Settings window's real page bar** — held, with no
/// user now, until `ASearchKeepsNoHistoryOfWhatWasTypedTests` is retargeted.
///
/// `MountedRender`'s window holds the page and nothing else: it has no bar, so a page's
/// `helmWindowToolbar` declaration reaches nobody. This adds a `MountedPageBar` to that window, listening
/// on the same `channel` the page was mounted with, so the page's tabs, actions and search arrive in the
/// bar's zones as they do in the real window. `HelmTestSupport` may not reach `HelmApp` (`Package.swift`'s
/// own "support may reach the shared plumbing, nothing may reach support"), which is why the fixture lives
/// in `HelmAppTests`, per `CLAUDE.md`'s "app-layer checks in `Tests/HelmAppTests`".
///
/// `selection` is set before the bar is constructed: the bar refreshes from `model.selection` in its
/// initialiser, so its first refresh already reads the page this fixture was built for. No `settle()` has
/// run by then; what the page declares later reaches the bar through the channel.
///
/// The bar reads four settings when it is built and its tabs zone reads a fifth,
/// `AppSettings.toolbarSwitcherStyle` (`MountedPageBar`'s own doc); a family that depends on one
/// pins it before building the fixture. Each bar's search zone holds an event monitor until it is
/// released, so a fixture is dropped in `tearDown`.
@MainActor
struct LivePageToolbarFixture {
    let mount: MountedRender
    let pageBar: MountedPageBar
    let model: SettingsModel
    let channel: HelmWindowToolbarChannel

    var bar: ShellPageBar { pageBar.bar }

    init<V: View>(_ view: V, selection: SettingsSelection, width: CGFloat, height: CGFloat,
                 appearance: NSAppearance.Name = .aqua, titlebarIsTransparent: Bool = true) {
        let channel = HelmWindowToolbarChannel()
        let model = SettingsModel(host: ModuleHost.shared)
        model.selection = selection
        let mount = MountedRender(view, width: width, height: height,
                                  appearance: appearance, channel: channel)
        self.mount = mount
        self.pageBar = MountedPageBar(model: model, channel: channel, in: mount.window,
                                      titlebarIsTransparent: titlebarIsTransparent)
        self.model = model
        self.channel = channel
    }

    /// Settles the page and lays the bar out after every turn, so a reading of the bar's frames sees the
    /// zones where the page's latest declaration put them.
    func settle(_ turns: Int = 25) {
        for _ in 0..<turns {
            pageBar.layout()
            mount.settle(1)
        }
        pageBar.layout()
    }

    func drop() {
        pageBar.remove()
        mount.drop()
    }
}
