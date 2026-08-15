import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// Opening the editor is one dry run, not two.
///
/// The sheet carried a bare `.task` at its root *and* a `.task(id: previewKey)`
/// on the dry-run section, and both fire on appearance — so every opening paid
/// for two full reads of the watched folder behind the sheet, back to back,
/// with the second answer overwriting an identical first. The keyed task is
/// the one that has to stay: it re-asks as the rule is written. The bare one
/// was the same request with no way to be anything else.
///
/// Mounted for real rather than driven through the view model, because the
/// defect is in the view's modifiers: no call the model exposes says how many
/// times SwiftUI ran its tasks.
@MainActor
final class TheEditorAsksForOneDryRunTests: XCTestCase {

    private var window: NSWindow?

    /// The window holds the editor, and the editor holds a view model with a
    /// task in it. Taken down on the actor the window lives on.
    override func tearDown() async throws {
        await MainActor.run {
            window?.contentView = nil
            window = nil
        }
        try await super.tearDown()
    }

    private func dryRuns(on wire: AutopilotWire) -> Int {
        wire.commands.filter { $0 == .previewDraft }.count
    }

    func testOpeningTheEditorAsksForOneDryRunNotTwo() {
        let rule = Rule(id: "r", name: "r", conditions: [.fileExtension(["pdf"])],
                        action: .sortIntoSubfolder(.kind))
        let folder = WatchedFolder(id: "f", path: "/tmp/watched", rules: [rule])
        let wire = AutopilotWire(folders: [folder])
        let rvm = AutopilotViewModel(vm: ModuleViewModel(transport: wire))

        let host = NSHostingView(rootView: RuleEditor(rvm: rvm, folder: folder, rule: rule))
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                             styleMask: [.titled], backing: .buffered, defer: false)
        panel.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 620)
        panel.layoutIfNeeded()
        window = panel

        // First that the ask happened at all: a sheet that never ran a dry run
        // would pass «not two» while the editor promised one on the screen.
        settle(until: { self.dryRuns(on: wire) >= 1 })
        XCTAssertGreaterThanOrEqual(dryRuns(on: wire), 1,
                                    "the editor never asked for a dry run at all")

        // Then that no second ask is on its way. The rule has not changed, so
        // the keyed task has nothing to re-ask about.
        settle(turns: 60)
        XCTAssertEqual(dryRuns(on: wire), 1,
                       "opening the editor read the whole watched folder twice")
    }

    /// Turns of the run loop, until the condition holds or patience runs out.
    private func settle(turns: Int = 200, until done: () -> Bool = { false }) {
        for _ in 0..<turns {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            if done() { return }
        }
    }
}
