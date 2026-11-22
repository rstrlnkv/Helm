import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Show in Finder and Copy Path are offered when a menu is built and pressed later. What was offered is not what is true at the press:
/// the Hidden card may have locked (the path of a hidden app is as private as its name), or the app may have been hidden in between. A press
/// hands the closure nothing it would not hand if the menu were built now. An app removed or moved is the sibling class's
/// (`AFileActionNamesThePathTheCatalogHoldsNowTests`).
@MainActor final class AFileActionActsOnlyWhileItsOfferStandsTests: XCTestCase {
    private let hiddenApp = HiddenRig.unreconciled().apps[HiddenRig.hidden]!

    private func wired(_ rig: HiddenRig) -> (copied: () -> [String], revealed: () -> [String]) {
        var copied: [String] = [], revealed: [String] = []
        rig.state.onCopyPath = { path, _ in copied.append(path) }
        rig.state.onRevealApp = { revealed.append($0) }
        return ({ copied }, { revealed })
    }

    private func snapshot(_ apps: [CatalogApp], hidden: Set<AppID>) -> LaunchpadSnapshot {
        var layout = LaunchpadLayout(items: apps.map { .app($0.id) })
        layout.hidden = hidden
        return LaunchpadSnapshot(apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }), order: apps.map(\.id),
                                 layout: layout, catalogComplete: true, layoutRead: .absent)
    }

    func testAMenuBuiltInTheUnlockedHiddenCardDoesNothingOnceTheCardLocked() async {
        let rig = HiddenRig(.immediate(.success))
        let seen = wired(rig)
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.gate.settled()
        let files = rig.state.fileActions(for: hiddenApp)
        XCTAssertNotNil(files, "the subject: the menu was built while the card was open")
        files?.copyPath()
        XCTAssertEqual(seen.copied(), ["/Applications/h.app"], "the control: while unlocked it acts")

        rig.gate.lock()
        XCTAssertEqual(rig.gate.phase, .locked, "the subject: the gate locked behind the open menu")
        files?.copyPath()
        files?.reveal()
        XCTAssertEqual(seen.copied(), ["/Applications/h.app"], "a locked card hands no path out")
        XCTAssertEqual(seen.revealed(), [], "nor shows the file")
    }

    func testAnAppHiddenAfterTheMenuWasBuiltHandsNoPath() {
        let rig = HiddenRig(.immediate(.success))
        let seen = wired(rig)
        let visible = HiddenRig.unreconciled().apps["a"]!
        let files = rig.state.fileActions(for: visible)
        rig.state.update(snapshot: snapshot([visible, hiddenApp], hidden: ["a", HiddenRig.hidden]))
        files?.copyPath()
        XCTAssertEqual(seen.copied(), [], "a now hidden app's path stays private")
    }
}
