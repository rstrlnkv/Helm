import AppKit
import SwiftUI
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// **A page mounted under the header row of the card** — the fixture of the families that type into the
/// search field the row draws.
///
/// The row is the one the settings window draws (`helmCardHeader`, `HelmPageHeader.swift`), with
/// `helmHeaderInCard` set the way `makeShell` sets it, so a page declares into the preference the row reads
/// (`helmWindowToolbar`) and the row draws what it declared, in the mount's own hosting view. The families that use it
/// live in `HelmAppTests` because the fixture needs the host's own types (`ShellPageIdentity`; `CLAUDE.md`:
/// app-layer checks in `Tests/HelmAppTests`).
///
/// `selection` is what the row's name and status are read from (`ShellPageIdentity`); a caller settles
/// (`settle(_:)`) before it reads what the page declared, since the declaration reaches the row a turn
/// after the page mounts.
@MainActor
struct LivePageUnderTheHeaderFixture {
    let mount: MountedRender

    init<V: View>(_ view: V, selection: SettingsSelection, width: CGFloat, height: CGFloat,
                  appearance: NSAppearance.Name = .aqua) {
        let identity = ShellPageIdentity.of(selection, host: ModuleHost.shared)
        mount = MountedRender(view.frame(maxWidth: .infinity, maxHeight: .infinity)
                                  .environment(\.helmHeaderInCard, true)
                                  .helmCardHeader(symbol: identity.symbol, tint: identity.tint,
                                                  title: identity.title, status: identity.status),
                              width: width, height: height, appearance: appearance)
    }

    /// Settles the mount (`MountedRender.settle`), `turns` turns.
    func settle(_ turns: Int = 25) {
        mount.settle(turns)
    }

    func drop() {
        mount.drop()
    }

    /// The field of the header row's search (`MountedRender.searchField`); nil where the page declared none.
    var searchField: NSSearchField? {
        mount.searchField
    }
}
