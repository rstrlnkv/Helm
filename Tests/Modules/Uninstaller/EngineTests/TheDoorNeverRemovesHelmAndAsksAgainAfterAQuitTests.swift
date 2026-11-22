import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **The door refuses Helm's own family, and asks the verdict again after the quit wait.**
///
/// The running app's id, an id under it with a dot (Helm Dev, the Launchpad helper) and its own bundle
/// path are never offered: removing the app that is asking would take the door with it. The quit loop
/// is long enough for a bundle to be swapped for another app's; the verdict is read again before the
/// move, and a changed one moves nothing.
final class TheDoorNeverRemovesHelmAndAsksAgainAfterAQuitTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws { home = scratchDirectory("launchpad-own") }

    private func engine(trash: FakeTrash, running: FakeRunning = FakeRunning(running: []),
                        ownPath: String) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(), trash: trash, running: running,
                          ownApp: ("com.helm.app", ownPath))
    }

    func testHelmItselfItsDevCopyAndItsHelperAreRefusedAndItsLookalikeIsNot() async throws {
        let own = try writeAppBundle(home.appendingPathComponent("Applications/Helm.app"), id: "com.helm.app")
        let ids = ["com.helm.app": "Helm", "com.helm.app.dev": "Helm Dev",
                   "com.helm.app.launchpad": "Launchpad", "com.helm.application": "Other"]
        for (id, name) in ids {
            let path = try writeAppBundle(home.appendingPathComponent("Applications/\(name).app"), id: id)
            let trash = FakeTrash()
            let door = engine(trash: trash, ownPath: own)
            let candidate = AppRemovalCandidate(bundleID: id, path: path, name: name)

            let verdicts = await door.removalVerdicts(for: [candidate])
            let report = await door.removeApp(candidate, quittingIfRunning: false)

            if id == "com.helm.application" {
                XCTAssertEqual(verdicts, [.removable], "a lookalike one dot away was taken for Helm")
            } else {
                XCTAssertEqual(verdicts, [.refused(.notOffered)], "id «\(id)»")
                XCTAssertEqual(report.outcome, .refused, "id «\(id)»")
                XCTAssertEqual(trash.trashed, [], "id «\(id)» reached the Trash port")
            }
        }
    }

    func testTheRunningHelmsOwnBundleIsRefusedWhateverIdItCarries() async throws {
        let own = try writeAppBundle(home.appendingPathComponent("Applications/Helm.app"), id: "com.acme.renamed")
        let trash = FakeTrash()
        let door = engine(trash: trash, ownPath: own)

        let verdicts = await door.removalVerdicts(for: [
            AppRemovalCandidate(bundleID: "com.acme.renamed", path: own, name: "Helm")])

        XCTAssertEqual(verdicts, [.refused(.notOffered)])
    }

    func testABundleSwappedWhileTheAppWasQuitMovesNothing() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/Tool.app"), id: "com.acme.tool")
        let candidate = AppRemovalCandidate(bundleID: "com.acme.tool", path: path, name: "Tool")
        let swapping = SwapsTheBundleOnQuit(path: path, newID: "com.acme.other")
        let trash = FakeTrash()
        let door = UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(), trash: trash,
                                     running: swapping)

        let report = await door.removeApp(candidate, quittingIfRunning: true)

        XCTAssertTrue(swapping.quitAsked, "precondition: the app was quit")
        XCTAssertEqual(report.outcome, .refused)
        XCTAssertEqual(trash.trashed, [], "a bundle that changed during the quit was moved")
    }
}

/// An app that is up until asked to quit, and whose bundle is another app's by the time it is gone.
private final class SwapsTheBundleOnQuit: RunningAppsPort, @unchecked Sendable {
    private let lock = NSLock()
    private var up = true, asked = false
    private let path: String, newID: String
    init(path: String, newID: String) { self.path = path; self.newID = newID }
    var quitAsked: Bool { lock.withLock { asked } }
    func isRunning(bundleID: String) -> Bool { lock.withLock { up && bundleID == "com.acme.tool" } }
    func quit(bundleID: String, force: Bool) {
        lock.withLock { up = false; asked = true }
        _ = try? writeAppBundle(URL(fileURLWithPath: path), id: newID)
    }
}
