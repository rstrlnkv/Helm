import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A scan root that is a symbolic link.
///
/// A root that is not there walks to nothing, and an empty walk reported as a
/// finding is «проверено, чисто» about a folder nobody looked in. A symlink to
/// a directory is such a root: `fileExists(atPath:isDirectory:)` follows the
/// link, while `FileManager.enumerator(at:)` does not descend through a link
/// handed to it as the root and yields nothing (pinned as a premise below).
///
/// No attacker is needed: moving `~/Downloads` onto an external drive and
/// leaving a symlink behind is an ordinary macOS move, and Helm keeps the path
/// the person picked.
final class ScanRootSymlinkTests: XCTestCase {

    private var made: [URL] = []

    override func tearDown() {
        for url in made.reversed() { try? FileManager.default.removeItem(at: url) }
        made = []
        super.tearDown()
    }

    /// A real directory in the home with one file in it.
    private func directoryInHome() throws -> URL {
        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("helm-scan-root-target-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        made.append(url)
        try Data("x".utf8).write(to: url.appendingPathComponent("inside.txt"))
        return url
    }

    /// A symlink whose own path is inside the home, pointing wherever asked.
    private func linkInHome(to target: String) throws -> String {
        let link = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("helm-scan-root-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                  withDestinationPath: target)
        made.append(link)
        return link.path
    }

    /// What the scanners do with a root: one enumerator, no symlink resolution.
    private func filesTheWalkWouldSee(_ root: String) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
        else { return 0 }
        var seen = 0
        for case _ as URL in enumerator { seen += 1 }
        return seen
    }

    /// The premise, asserted: if a macOS starts following a symlinked root,
    /// this fails first and the reasoning below is void rather than silently
    /// wrong.
    func testTheWalkYieldsNothingThroughASymlinkedRoot() throws {
        let target = try directoryInHome()
        let link = try linkInHome(to: target.path)
        XCTAssertEqual(filesTheWalkWouldSee(target.path), 1, "the directory itself")
        XCTAssertEqual(filesTheWalkWouldSee(link), 0, "the same directory through a link")
    }

    /// The gate hands back the **target**, so the caller walks a directory the
    /// enumerator can descend into. A link to a directory inside the home is
    /// ordinary and the scan should work; returning the path means the gate
    /// cannot approve one path while the caller walks another.
    func testASymlinkedRootResolvesToSomethingTheWalkCanRead() throws {
        let target = try directoryInHome()
        let link = try linkInHome(to: target.path)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: link, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue,
                      "premise: the existence check follows the link and sees a directory")

        let resolved = try XCTUnwrap(ScanRoot.resolve(link))
        XCTAssertNotEqual(resolved, link, "handed back the link the walk cannot enter")
        XCTAssertEqual(filesTheWalkWouldSee(resolved), 1,
                       "the approved path walks to nothing — «проверено, чисто» "
                       + "about a folder the scan never entered")
    }

    /// The gate's contract: `ScanRoot` promises "the user's home and anything
    /// inside it", so a link out of the home is refused once resolved.
    /// `PathCanonical.resolvingAncestors` leaves the leaf unresolved, which is
    /// right for removal (trash the link, not its target) and wrong here: an
    /// unresolved leaf would be a read of the whole volume with nobody at the
    /// keyboard.
    func testALinkOutOfTheHomeIsRefusedOnItsOwn() throws {
        XCTAssertNil(ScanRoot.resolve(try linkInHome(to: "/")), "the volume root")
        XCTAssertNil(ScanRoot.resolve(try linkInHome(to: "/Users")), "every account")
        XCTAssertNil(ScanRoot.resolve(try linkInHome(to: "/Library")), "outside the home")
    }

    /// The control, so a fix cannot be "refuse everything with a link in it".
    /// A real directory inside the home is still a root.
    func testAnOrdinaryDirectoryInTheHomeIsStillAllowed() throws {
        XCTAssertNotNil(ScanRoot.resolve(try directoryInHome().path))
    }

    /// `$HOME/link/.`, with `link` pointing outside the home, is refused.
    /// `standardizingPath` strips the `/.`, so a check would judge the bare
    /// link, while `FileManager.enumerator` follows the `/.` form, so the walk
    /// would go where the check never looked.
    ///
    /// One assertion for the refusal and one for the walk, because either alone
    /// would pass on a gate that is right for the wrong reason.
    func testTheTrailingDotSpellingCannotEscapeEither() throws {
        // A small directory of our own outside the home, not `/Users`: the
        // premise assertion below walks whatever it points at.
        let outside = scratchDirectory("scan-outside")
        made.append(outside)
        try Data("x".utf8).write(to: outside.appendingPathComponent("secret.txt"))

        let link = try linkInHome(to: outside.path)
        XCTAssertNil(ScanRoot.resolve(link + "/."), "approved a way out of the home")
        XCTAssertGreaterThan(filesTheWalkWouldSee(link + "/."), 0,
                             "premise: this spelling is the one the walk follows")
    }
}
