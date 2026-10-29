import HelmTestSupport
import XCTest
@testable import HelmRuntime
@testable import Module_Duplicates_Engine

/// Which gate guards this module's deletions.
///
/// There are two in `HelmRuntime` and they answer different questions.
/// `RemovableScope` asks what belongs to an *application* — its roots are
/// `~/Library`, `/Applications` and the shared `/Library` folders — which is
/// right for the uninstaller and fatal here: a duplicate finder pointed at
/// `~/Downloads` would refuse every file it found, offering a basket that
/// silently accepts nothing. `UserFileScope` asks what belongs to the *user*,
/// which is the question this module is asking.
///
/// This test exists because the finder was wired to the wrong one when it moved
/// out of Disk, and the symptom — every checkbox disabled — looks from a
/// distance like a permissions problem rather than a mistake.
final class DuplicatesRemovalGateTests: XCTestCase {

    private var home: String { NSHomeDirectory() }

    /// The folders people actually keep duplicates in.
    func testOrdinaryUserFilesCanBeBasketed() {
        for path in ["\(home)/Downloads/photo.jpg",
                     "\(home)/Documents/report.pdf",
                     "\(home)/Desktop/scan copy.png",
                     "/Volumes/Backup/Photos/img.raw"] {
            XCTAssertTrue(UserFileScope.isRemovable(path), path)
            XCTAssertFalse(RemovableScope.isRemovable(path),
                           "\(path) — the app-cleanup gate would refuse this")
        }
    }

    /// And what must never be offered, whatever the walk turned up.
    func testSystemFilesAreStillRefused() {
        for path in ["/System/Library/Fonts/Helvetica.ttc", "/usr/bin/swift",
                     "/bin/sh", home, "/Users", "/"] {
            XCTAssertFalse(UserFileScope.isRemovable(path), path)
        }
    }

    /// The engine reports refusals rather than dropping them, so a batch that
    /// mixes the two comes back split, not shortened.
    func testAMixedBatchIsSplitRatherThanShortened() {
        let (allowed, refused) = UserFileScope.partition([
            "\(home)/Downloads/a.bin", "/System/Library/x", "\(home)/Desktop/b.bin",
        ])
        XCTAssertEqual(allowed.count, 2)
        XCTAssertEqual(refused, ["/System/Library/x"])
    }

    /// The engine has the last word: a path the scope gate refuses is reported
    /// refused and **not attempted**. The recorder is the engine's `trashing:`
    /// port and the verification answers `.identical` for everything, so the
    /// only thing between the path and the recorder is the gate — with the
    /// partition bypassed the path reaches the recorder and this goes red.
    func testAPathTheGateRefusesIsRefusedByTheEngineAndNotAttempted() async {
        let recorder = TrashRecorder()
        let engine = DuplicatesEngine(settings: suiteSealGuard(),
                                      trashing: recorder.trashing,
                                      verifying: { { _, _ in .identical } })
        let path = "/System/Library/Fonts/Helvetica.ttc"

        let result = await engine.trash([DuplicatePlan(remove: path, keep: "\(home)/Downloads/keep.bin")])

        XCTAssertEqual(result.refused.map(\.path), [path])
        XCTAssertEqual(result.refused.map(\.reason), [.outOfScope])
        XCTAssertEqual(recorder.count, 0, "the engine handed a refused path to the Trash")
        XCTAssertTrue(result.removed.isEmpty)
    }
}
