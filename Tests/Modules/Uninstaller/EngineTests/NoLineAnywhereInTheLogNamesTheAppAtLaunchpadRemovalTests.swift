import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// **No category of the log names the app or its id, whatever macOS says and whichever scan line is written.**
///
/// `TheLogDoesNotNameTheAppAtLaunchpadRemovalTests` reads the Uninstaller's own category with a refusal
/// whose message is «denied». The system's sentence for a bundle quotes its display name, and the
/// scan's line about a neighbouring app is written by a different path: both are read here, in every
/// category the tail holds, the preview's lines included.
final class NoLineAnywhereInTheLogNamesTheAppAtLaunchpadRemovalTests: XCTestCase {

    private let secret = "SecretApp\(UUID().uuidString.prefix(6))"
    private var id: String { "com.secret.\(secret.lowercased())" }
    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("launchpad-log-all")
        tailTheLog()
    }

    /// macOS's own sentence, with the name the person sees and the id in it.
    private struct QuotingTrash: TrashPort {
        let said: String
        func trashItem(_ url: URL) -> TrashOutcome {
            TrashOutcome(succeeded: false, errorCode: 513, message: said)
        }
    }

    private func assertNoLineNames(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let entries = HelmLog.shared.recentEntries()
        XCTAssertFalse(entries.isEmpty, "\(what): the log held nothing, so an absence proves nothing",
                       file: file, line: line)
        let naming = entries.filter {
            $0.message.contains(secret) || $0.message.lowercased().contains(id)
        }
        XCTAssertTrue(naming.isEmpty, "\(what): \(naming.map { "\($0.category): \($0.message)" })",
                      file: file, line: line)
    }

    func testASentenceFromMacOSThatQuotesTheAppIsNotWrittenToAnyCategory() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/\(secret).app"), id: id)
        _ = try write("Library/Caches/\(id)/data", in: home)
        let said = "“\(secret)” couldn’t be moved to the Trash because \(path) and \(id) are protected"
        let engine = UninstallerEngine(home: home, apps: FakeApps(), fs: FMFileSystem(),
                                       trash: QuotingTrash(said: said), running: FakeRunning(running: []))
        let candidate = AppRemovalCandidate(bundleID: id, path: path, name: secret)

        let report = await engine.removeApp(candidate, quittingIfRunning: false)

        XCTAssertEqual(report.outcome, .refused, "precondition: the refusals were written")
        XCTAssertFalse(HelmLog.shared.recentEntries().filter { $0.message.hasPrefix("trash refused") }.isEmpty,
                       "precondition: the refusal line exists")
        assertNoLineNames("a refusal quoting the app")
    }

    func testThePreviewAndTheScanLineAboutANeighbourNameNothing() async throws {
        let path = try writeAppBundle(home.appendingPathComponent("Applications/\(secret).app"), id: id)
        // A leftover that a longer id of an installed neighbour owns: the scan refuses it and says so.
        let neighbour = id + ".staging"
        _ = try write("Library/Caches/\(neighbour)/data", in: home)
        let apps = FakeApps.installed([neighbour])
        let engine = UninstallerEngine(home: home, apps: apps, fs: FMFileSystem(), trash: FakeTrash(),
                                       running: FakeRunning(running: [id]))
        let candidate = AppRemovalCandidate(bundleID: id, path: path, name: secret)

        _ = await engine.removalPreview(candidate)
        _ = await engine.removeApp(candidate, quittingIfRunning: true)

        XCTAssertTrue(HelmLog.shared.recentEntries().contains { $0.message.contains("refused 1 candidate") },
                      "precondition: the scan wrote its line about the neighbour")
        assertNoLineNames("the preview and a quit")
    }
}
