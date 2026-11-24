import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The Full Disk Access probe asks each of its paths for one byte. A path it
/// cannot get a byte out of whatever the grant says is not a probe: it answers
/// "denied" on a Mac that granted everything, and it is reached exactly when the
/// paths before it have failed, which on an ad-hoc signed build is the state
/// every update leaves behind. A directory is such a path.
final class TheProbeAsksPathsItCanAnswerFromTests: XCTestCase {

    /// The control: the read shape fails on an ordinary directory nothing
    /// protects, `/tmp` as flatly as a Messages database, for another reason.
    func testTheReadShapeCannotSucceedOnADirectory() throws {
        let root = scratchDirectory("probe-shape")
        let file = try write("readable", in: root, bytes: 1)

        XCTAssertTrue(PermissionCheck.canRead(file),
                      "the shape cannot read a plain file, so nothing below means anything")
        XCTAssertFalse(PermissionCheck.canRead(root),
                       "a directory answered the probe, so this check proves nothing")
    }

    /// And no path the probe ships is one of those.
    ///
    /// Judged only on the paths that exist here, because a path absent on this
    /// Mac is a path this Mac cannot say anything about — so the count is
    /// asserted too, or the loop passes by being empty. `isDirectory` is read
    /// through `stat`, which TCC does not gate: a probe path can be reported
    /// present, and its kind read, by a process with no grant at all.
    func testNoProbePathIsADirectory() throws {
        var judged: [String] = []
        for url in PermissionCheck.probeURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            judged.append(url.path)
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            XCTAssertEqual(isDirectory, false, """
                \(url.path) is a directory, so it can never hand the probe a byte — it reports \
                "no Full Disk Access" on a Mac that granted it
                """)
        }

        XCTAssertFalse(judged.isEmpty, """
            none of the probe's paths exists on this Mac, so the probe answers "denied" here \
            whatever the grant is and the loop above judged nothing
            """)
    }
}
