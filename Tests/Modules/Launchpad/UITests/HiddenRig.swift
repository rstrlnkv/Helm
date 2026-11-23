import Foundation
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A window's state in the category view with one app, `h`, that the person hid, and a gate over a fake prompt.
/// `unreconciled`: the snapshot is built by hand and still holds `h` in `layout.items` and in a folder, as no engine would hand it,
/// so that the guards that keep a hidden app out are the only thing between it and the page.
@MainActor final class HiddenRig {
    static let hidden = "h"
    let state: LaunchpadScreenState
    let gate: LaunchpadHiddenGate
    let fake: FakeAuthPort

    init(_ mode: FakeAuthPort.Mode) {
        fake = FakeAuthPort(mode)
        gate = LaunchpadHiddenGate(port: fake)
        state = LaunchpadScreenState(geometry: .make(for: CGSize(width: 1280, height: 800), topSafe: 0), view: .categories, hidden: gate)
        state.setShown(true)
        state.update(snapshot: Self.unreconciled())
    }

    static func unreconciled() -> LaunchpadSnapshot {
        let apps = [CatalogApp(id: "a", name: "Alpha", path: "/Applications/a.app"), CatalogApp(id: hidden, name: "Alphabet", path: "/Applications/h.app")]
        var layout = LaunchpadLayout(items: [.app("a"), .app(hidden),
                                             .folder(LaunchpadLayout.Folder(id: UUID(), name: "F", apps: [hidden, "a"]))])
        layout.hidden = [hidden]
        return LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: apps.map(\.id),
                                 layout: layout, catalogComplete: true, layoutRead: .absent)
    }

    /// Every app id the state draws or holds anywhere: the pages, the folder tiles' apps, the card.
    var everythingShown: [String] {
        let tiles = state.pages.joined().flatMap { entry -> [String] in
            if case .folder(_, _, let apps, _) = entry { return [entry.id] + apps.map(\.id) }
            return [entry.id]
        }
        return tiles + state.cardEntries.map(\.id) + state.folderApps.map(\.id) + (state.openFolder.map { [$0.uuidString] } ?? [])
    }

    var hiddenIsShown: Bool { everythingShown.contains(Self.hidden) }

    var hiddenTile: String { LaunchpadHiddenBlock.id.uuidString }

    /// The arrow keys' choice moved onto the Hidden tile, which is last.
    func chooseHiddenTile() {
        let ids = state.pages.joined().map(\.id)
        for _ in 0..<ids.count where state.selection != ids.firstIndex(of: hiddenTile) { state.move(dx: 1, dy: 0) }
    }
}
