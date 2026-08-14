import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// Who a file is, as opposed to what it is called.
///
/// The third place in the app to want device and inode together — `StampMark`
/// asks so a mark cannot be copied onto the file next to it, and Autopilot's
/// undo asks so a return moves the file Helm moved rather than whatever is
/// sitting at that path now.
final class FileIdentityTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("identity")
    }

    func testAFileIsTheSameFileAfterARename() throws {
        let file = try write("a.pdf", in: root)
        let before = try XCTUnwrap(PathCanonical.identity(of: file.path))
        let renamed = root.appendingPathComponent("b.pdf")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertEqual(PathCanonical.identity(of: renamed.path), before)
    }

    /// The case the undo turns on: a file put back where a rule took it from,
    /// with something else now sitting at the old path.
    func testTwoFilesAreNotOneFile() throws {
        let one = try write("a.pdf", in: root)
        let two = try write("b.pdf", in: root)
        XCTAssertNotEqual(PathCanonical.identity(of: one.path),
                          PathCanonical.identity(of: two.path))
    }

    func testNothingAtThePathHasNoIdentity() {
        XCTAssertNil(PathCanonical.identity(of: root.appendingPathComponent("gone").path))
    }

    /// `lstat`, matching `RuleStamp`: the identity of a symlink is the link's
    /// own, never the target's. A link that answered with its target's identity
    /// would let a return move the target.
    func testALinkIsNotTheFileItPointsAt() throws {
        let file = try write("real.pdf", in: root)
        let link = root.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertNotEqual(PathCanonical.identity(of: link.path),
                          PathCanonical.identity(of: file.path))
    }
}
