import AppKit
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Copy Path of a hidden app is marked for a clipboard manager (`ConcealedType`, `TransientType`), and of any other app is the plain
/// text. Read off a pasteboard of the test's own name, never the general one. Whether a manager honours the markers is not measured.
@MainActor final class ACopiedPathOfAHiddenAppIsMarkedConcealedTests: XCTestCase {
    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("helm.test.launchpad.\(UUID().uuidString)"))
        addTeardownBlock { board.releaseGlobally() }
        return board
    }

    func testAConcealedCopyCarriesBothMarkersAndThePath() throws {
        let b = board()
        XCTAssertTrue(LaunchpadPasteboard(named: b.name).copy(path: "/Applications/h.app", concealed: true))
        let types = try XCTUnwrap(b.types)
        XCTAssertTrue(types.contains(LaunchpadPasteboard.concealedType))
        XCTAssertTrue(types.contains(LaunchpadPasteboard.transientType))
        XCTAssertEqual(b.string(forType: .string), "/Applications/h.app")
    }

    func testAPlainCopyCarriesNoMarker() throws {
        let b = board()
        XCTAssertTrue(LaunchpadPasteboard(named: b.name).copy(path: "/Applications/a.app", concealed: false))
        let types = try XCTUnwrap(b.types)
        XCTAssertFalse(types.contains(LaunchpadPasteboard.concealedType))
        XCTAssertFalse(types.contains(LaunchpadPasteboard.transientType))
        XCTAssertEqual(b.string(forType: .string), "/Applications/a.app")
    }

    func testThePressTellsTheWriterWhetherTheAppIsHidden() async {
        let rig = HiddenRig(.immediate(.success))
        var seen: [Bool] = []
        rig.state.onCopyPath = { _, concealed in seen.append(concealed) }
        rig.state.fileActions(for: HiddenRig.unreconciled().apps["a"]!)?.copyPath()
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.gate.settled()
        rig.state.fileActions(for: HiddenRig.unreconciled().apps[HiddenRig.hidden]!)?.copyPath()
        XCTAssertEqual(seen, [false, true], "a visible app's copy is plain, the Hidden card's is concealed")
    }
}
