import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The Full Disk Access probe asks each of its paths for one byte. A path it
/// cannot get a byte out of *whatever the grant says* is not a probe at all: it
/// answers "denied" on a Mac that granted everything, and it is reached exactly
/// when the paths before it have already failed — which, on an ad-hoc signed
/// build, is the state every update leaves behind.
///
/// `~/Library/Application Support/AddressBook` was such a path for as long as
/// the probe had four of them. It is a directory, it exists on every Mac, and it
/// sat last in the list, so the only run that ever opened it was the run where
/// the answer was already going to be "denied" — while being the one entry
/// pointed at a Contacts-gated subtree rather than a Full-Disk-gated file.
final class TheProbeAsksPathsItCanAnswerFromTests: XCTestCase {

    /// The control, and the whole reason the test below is worth writing: the
    /// read shape fails on an ordinary directory nothing protects. Measured
    /// rather than reasoned about — `/tmp` refuses this read as flatly as
    /// somebody's Messages database does, and for an entirely different reason.
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
