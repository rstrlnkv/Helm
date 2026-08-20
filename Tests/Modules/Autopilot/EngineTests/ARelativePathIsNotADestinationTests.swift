import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The gate's first question is «is this absolute», and it has to be asked
/// before anything resolves the path.
///
/// Both sibling gates open with it and both explain it in the same words:
/// `UserFileScope.isRemovable` and `ScanRoot.resolve` guard first and
/// canonicalize second, because every resolver builds a
/// `URL(fileURLWithPath:)` — which resolves a relative path against the
/// **process's working directory** and hands back something absolute. Resolve
/// first and the gate is handed an answer instead of a question.
///
/// `WatchScope` went straight to `URL(fileURLWithPath: rawPath)`, so a rule
/// whose destination was `relative/path` — or the empty string, which is what a
/// truncated or forged plist degrades into — was judged as a folder under the
/// working directory. It is latent rather than live: a bundle launched by
/// LaunchServices or launchd has `/` for a working directory, and there
/// everything relative falls outside the home and is refused. It bites the
/// developer loop, where the binary is started from a shell sitting in the
/// home. A gate must not depend on how the program was launched.
///
/// **The working directory is read rather than changed.** The home is a
/// parameter of the gate, so passing the *parent* of the working directory
/// reproduces «the process is running somewhere inside the home» exactly,
/// without one test reaching into state the whole process shares.
final class ARelativePathIsNotADestinationTests: XCTestCase {

    /// A home that really does contain the working directory, which is the
    /// arrangement that makes the defect visible.
    private func homeContainingTheWorkingDirectory() throws -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let parent = (cwd as NSString).deletingLastPathComponent
        // Asserted rather than skipped: a test that quietly opts out of its own
        // subject passes for ever without checking anything.
        XCTAssertNotEqual(parent, "/", "the working directory is too shallow to stand in for a home")
        XCTAssertNotEqual(parent, cwd)
        return parent
    }

    func testARelativeDestinationIsRefused() throws {
        let home = try homeContainingTheWorkingDirectory()
        XCTAssertFalse(WatchScope.allows("relative/path", home: home))
        XCTAssertFalse(WatchScope.allows("Sorted", home: home))
        XCTAssertFalse(WatchScope.allows("./Sorted", home: home))
    }

    /// The empty string is the shape a missing value takes on the way through a
    /// plist, and `URL(fileURLWithPath: "")` is the working directory itself.
    func testTheEmptyPathIsRefused() throws {
        let home = try homeContainingTheWorkingDirectory()
        XCTAssertFalse(WatchScope.allows("", home: home))
    }

    /// A path that walks up out of the working directory is still relative, and
    /// the answer is the same for the same reason.
    func testARelativePathThatClimbsIsRefused() throws {
        let home = try homeContainingTheWorkingDirectory()
        XCTAssertFalse(WatchScope.allows("../Sorted", home: home))
        XCTAssertFalse(WatchScope.allows("..", home: home))
    }

    /// And the guard refuses relativity, not everything: an absolute
    /// destination inside the same home is still allowed, or the "fix" would be
    /// a gate that lets nothing through.
    func testAnAbsoluteDestinationInThatHomeStillPasses() throws {
        let home = try homeContainingTheWorkingDirectory()
        XCTAssertTrue(WatchScope.allows(home + "/Downloads/Sorted", home: home))
    }
}
