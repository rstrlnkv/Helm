import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **An app asked for through the door meets the Uninstaller's gate where the deleting is.**
///
/// `SystemApp.isSystem` was the page's alone: a `com.apple.` app in `/Applications` is a row without a
/// checkbox, and the engine would have taken a batch that named it. The door's callers are not that page,
/// so `removalVerdict` carries the refusals and `removeApp` and `removalPreview` ask it again before
/// anything is scanned or quit. Each refusal below runs with the app **up** and the quit **agreed**: a
/// missing gate then shows as a quit and a move, not as a quiet pass.
final class AnAppRemovedFromLaunchpadPassesTheUninstallersGateInTheEngineTests: XCTestCase {

    private var home: URL!
    private let toolID = "com.acme.tool"

    override func setUpWithError() throws {
        home = scratchDirectory("launchpad-gate")
    }

    private func engine(trash: FakeTrash, running: FakeRunning) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(), trash: trash, running: running)
    }

    @discardableResult
    private func bundle(_ relative: String, id: String) throws -> String {
        try writeAppBundle(home.appendingPathComponent(relative), id: id)
    }

    /// Asks every door with the app up and the quit agreed, and says nothing moved or quit.
    private func assertRefused(_ candidate: AppRemovalCandidate, as why: AppRemovalVerdict.Refusal,
                               file: StaticString = #filePath, line: UInt = #line) async {
        let trash = FakeTrash()
        let running = FakeRunning(running: [candidate.bundleID, toolID])
        let engine = engine(trash: trash, running: running)

        let verdicts = await engine.removalVerdicts(for: [candidate])
        let ask = await engine.removalPreview(candidate)
        let report = await engine.removeApp(candidate, quittingIfRunning: true)

        XCTAssertEqual(verdicts, [.refused(why)], "the verdict", file: file, line: line)
        XCTAssertEqual(ask, .refused(why), "the preview was given for an app the gate refuses",
                       file: file, line: line)
        XCTAssertEqual(report.outcome, .refused, "the removal was not refused", file: file, line: line)
        XCTAssertEqual(trash.trashed, [], "a refused app reached the Trash port", file: file, line: line)
        XCTAssertEqual(running.quits.count, 0, "a refused app was quit", file: file, line: line)
    }

    func testAnAppleIdIsRefusedAsSystem() async throws {
        let path = try bundle("Applications/Notes.app", id: "com.apple.Notes")
        await assertRefused(AppRemovalCandidate(bundleID: "com.apple.Notes", path: path, name: "Notes"),
                            as: .system)
    }

    func testAnAppInTheSystemFolderIsRefusedAsSystem() async {
        await assertRefused(AppRemovalCandidate(bundleID: "com.apple.calculator",
                                                path: "/System/Applications/Calculator.app",
                                                name: "Calculator"), as: .system)
    }

    func testAThirdPartyAppInTheUtilitiesFolderIsNotOffered() async {
        await assertRefused(AppRemovalCandidate(bundleID: toolID,
                                                path: "/Applications/Utilities/Tool.app", name: "Tool"),
                            as: .notOffered)
    }

    func testAnAppInANestedVendorFolderIsNotOffered() async throws {
        let path = try bundle("Applications/Vendor/Tool.app", id: toolID)
        await assertRefused(AppRemovalCandidate(bundleID: toolID, path: path, name: "Tool"), as: .notOffered)
    }

    func testAnAppOutsideEveryAppFolderIsNotOffered() async throws {
        let path = try bundle("Downloads/Tool.app", id: toolID)
        await assertRefused(AppRemovalCandidate(bundleID: toolID, path: path, name: "Tool"), as: .notOffered)
    }

    func testALinkedBundleIsNotOffered() async throws {
        let real = try bundle("Elsewhere/Real.app", id: toolID)
        let link = home.appendingPathComponent("Applications/Linked.app")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real)
        await assertRefused(AppRemovalCandidate(bundleID: toolID, path: link.path, name: "Linked"),
                            as: .notOffered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: real), "the app behind the link went")
    }

    func testAPathWithDotDotIsNotOffered() async throws {
        let real = try bundle("Applications/Tool.app", id: toolID)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Applications/Sub"),
                                                withIntermediateDirectories: true)
        let spelled = home.path + "/Applications/Sub/../Tool.app"
        XCTAssertTrue(FileManager.default.fileExists(atPath: spelled), "precondition: the spelling leads to the app")
        await assertRefused(AppRemovalCandidate(bundleID: toolID, path: spelled, name: "Tool"), as: .notOffered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: real))
    }

    func testABundleWhoseInfoPlistSaysAnotherIdIsNotOffered() async throws {
        let path = try bundle("Applications/Tool.app", id: "com.acme.somethingelse")
        await assertRefused(AppRemovalCandidate(bundleID: toolID, path: path, name: "Tool"), as: .notOffered)
    }

    func testAnEmptyIdIsNotOffered() async throws {
        let path = try bundle("Applications/Tool.app", id: toolID)
        await assertRefused(AppRemovalCandidate(bundleID: "", path: path, name: "Tool"), as: .notOffered)
    }

    func testAnAppThatIsNotThereIsGone() async {
        await assertRefused(AppRemovalCandidate(bundleID: toolID,
                                                path: home.path + "/Applications/Missing.app", name: "Missing"),
                            as: .gone)
    }

    /// The control without which "refuse everything" passes the tests above: a plain app in the home's
    /// folder moves, and so does one in the Setapp folder.
    func testAnAllowedAppMoves() async throws {
        for relative in ["Applications/Tool.app", "Applications/Setapp/Tool.app"] {
            let path = try bundle(relative, id: toolID)
            let trash = FakeTrash()
            let engine = engine(trash: trash, running: FakeRunning(running: []))
            let candidate = AppRemovalCandidate(bundleID: toolID, path: path, name: "Tool")

            let verdicts = await engine.removalVerdicts(for: [candidate])
            let report = await engine.removeApp(candidate, quittingIfRunning: false)

            XCTAssertEqual(verdicts, [.removable], relative)
            XCTAssertEqual(report.outcome, .moved, relative)
            XCTAssertEqual(trash.trashed, [path], "\(relative): the bundle was not moved")
        }
    }
}
