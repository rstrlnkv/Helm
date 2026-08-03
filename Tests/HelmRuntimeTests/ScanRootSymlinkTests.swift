import XCTest
@testable import HelmRuntime

/// A scan root that is a symbolic link.
///
/// `ScanRoot`'s own doc gives the reason existence is checked at all:
///
/// > Existence is checked because a root that is not there produces an empty
/// > walk, and an empty walk reported as a finding is «проверено, чисто» about
/// > a folder nobody looked in.
///
/// A symlink to a directory is exactly such a root, and the gate cannot see it.
/// `fileExists(atPath:isDirectory:)` **follows** the link and answers "yes, and
/// it is a directory"; `FileManager.enumerator(at:)` **does not** descend
/// through a link handed to it as the root and yields nothing — measured on
/// this OS, and pinned as a premise below. `DuplicateScanner.walk` builds its
/// enumerator that way, so the search returns `[]` rather than nil, and
/// `DuplicatesEngine.backgroundScan` turns `[]` into
/// `ScanReport(bytes: 0, count: 0, items: [])` — a report, not a refusal. The
/// coordinator writes it into the journal as a scan that ran and found nothing.
///
/// **No attacker is needed.** The commonest way to get here is the ordinary
/// one: somebody moves `~/Downloads` (or `~/Movies`, or a photo library) onto
/// an external drive and leaves a symlink behind, which is a standard macOS
/// move. Helm stored the old path when the person picked it. Every background
/// scan from then on walks nothing, and the history says the folder is clean.
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

    /// **The premise, asserted rather than assumed.** If a future macOS starts
    /// following a symlinked root, this fails first and the reasoning behind the
    /// test below is void rather than silently wrong.
    func testTheWalkYieldsNothingThroughASymlinkedRoot() throws {
        let target = try directoryInHome()
        let link = try linkInHome(to: target.path)
        XCTAssertEqual(filesTheWalkWouldSee(target.path), 1, "the directory itself")
        XCTAssertEqual(filesTheWalkWouldSee(link), 0, "the same directory through a link")
    }

    /// The gate hands back the **target**, so the caller walks a directory the
    /// enumerator can descend into.
    ///
    /// This test was written asserting the opposite — that a symlinked root is
    /// refused — which was the right demand of the API it was written against:
    /// that one answered `true` about a link and left the caller to walk the
    /// link itself, reading nothing and recording «проверено, чисто».
    ///
    /// Refusing was never the better repair. A link to a directory inside the
    /// home is an ordinary thing on a Mac and the scan should simply work. What
    /// had to go was the shape that let the gate approve one path while the
    /// caller walked another; with `resolve` returning the path, the empty walk
    /// and the escape it was one step from are the same fix.
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

    /// The second half, and the one that is about the gate's stated contract
    /// rather than about a Foundation quirk. `ScanRoot` promises "the user's
    /// home and anything inside it"; `PathCanonical.resolvingAncestors`
    /// deliberately leaves the leaf unresolved, because trashing a link should
    /// remove the link and not its target — a rule written for a *removal* gate
    /// and inherited by a gate that answers a different question.
    ///
    /// Today the walk's refusal to follow the leaf is what stops this being a
    /// read of the whole volume with nobody at the keyboard. That is a stranger
    /// keeping this safe: the obvious repair for the empty walk above is to
    /// resolve the root before enumerating, and that repair turns this line
    /// into the disclosure it currently is not.
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

    /// The spelling that completed the escape, pinned so it cannot come back.
    ///
    /// Measured against the first version of this gate: `$HOME/link/.` where
    /// `link` points outside the home was **approved and walked**. Two
    /// reasonable decisions met and made a hole — `standardizingPath` strips the
    /// `/.` before the check sees it, so the gate judged the bare link and said
    /// yes; `FileManager.enumerator` treats the `/.` form as a directory and
    /// follows it, so the walk went where the check never looked.
    ///
    /// One assertion for the refusal and one for the walk, because either alone
    /// would pass on a gate that is right for the wrong reason.
    func testTheTrailingDotSpellingCannotEscapeEither() throws {
        // A small directory of our own outside the home, rather than `/Users`:
        // the premise assertion below walks whatever it points at, and pointing
        // it at a real account turned this one test into nine seconds against a
        // suite that runs in one.
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("helm-scan-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        made.append(outside)
        try Data("x".utf8).write(to: outside.appendingPathComponent("secret.txt"))

        let link = try linkInHome(to: outside.path)
        XCTAssertNil(ScanRoot.resolve(link + "/."), "approved a way out of the home")
        XCTAssertGreaterThan(filesTheWalkWouldSee(link + "/."), 0,
                             "premise: this spelling is the one the walk follows")
    }
}
