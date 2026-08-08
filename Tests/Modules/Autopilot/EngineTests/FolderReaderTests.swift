import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// What a rule is offered, and what it is not.
///
/// `FolderReader` is the only place a file becomes `FileFacts`, so it is the
/// only place a rule can be handed something it has no business seeing — the
/// insides of an app bundle, a file three levels down in a folder set to one.
/// Everything asserted here is about the *shape* of what comes back: which
/// names, at which levels. Sizes and dates come off the disk and are not this
/// module's to promise.
final class FolderReaderTests: XCTestCase {

    private var root: URL!
    private let reader = FolderReader()

    override func setUpWithError() throws {
        root = scratchDirectory("reader")
    }

    private func names(depth: Int) -> [String] {
        reader.facts(in: root.path, depth: depth).map(\.name).sorted()
    }

    // MARK: - Packages

    /// The one the module could get catastrophically wrong: an `.app` and an
    /// `.rtfd` are each one thing to a person, and a rule that saw their
    /// contents would move a few hundred pieces of an application into
    /// `Documents/` one file at a time.
    ///
    /// Two separate mechanisms have to hold for this — `.skipsPackageDescendants`
    /// on the enumerator, and `isPackage` cancelling `isDirectory` on the facts
    /// — and neither one alone is enough. The kind a package resolves to is
    /// deliberately not asserted: that comes from whatever UTIs the machine has
    /// registered, and an assertion on it would be a report about this Mac.
    func testAPackageIsOneThingRatherThanItsContents() throws {
        try write("Thing.app/Contents/MacOS/Thing", in: root)
        try write("Thing.app/Contents/Info.plist", in: root)
        try write("Note.rtfd/TXT.rtf", in: root)
        try write("plain.txt", in: root)

        for depth in [1, 2, 9] {
            XCTAssertEqual(names(depth: depth), ["Note.rtfd", "Thing.app", "plain.txt"],
                           "at depth \(depth) a package was taken apart")
        }

        let facts = reader.facts(in: root.path, depth: 9)
        for package in facts.filter({ $0.name.contains(".") && $0.name != "plain.txt" }) {
            XCTAssertFalse(package.isDirectory,
                           "\(package.name) is offered as a folder, so a folder rule will act on it")
            XCTAssertNotEqual(package.kind, .folder,
                              "\(package.name) is offered as a folder, so a folder rule will act on it")
        }
    }

    // MARK: - Depth

    /// Depth 1 is the folder's own contents — which includes its subfolders as
    /// *things*, without their contents. Worth stating, because it means the
    /// `Images/` a sort rule created a moment ago is itself offered back to the
    /// rules on the next sweep.
    func testDepthOneIsTheFoldersOwnContentsIncludingItsSubfolders() throws {
        try write("a.pdf", in: root)
        try write("sub/b.pdf", in: root)
        try write("sub/deeper/c.pdf", in: root)

        XCTAssertEqual(names(depth: 1), ["a.pdf", "sub"])
        XCTAssertEqual(names(depth: 2), ["a.pdf", "b.pdf", "deeper", "sub"])
        XCTAssertEqual(names(depth: 3), ["a.pdf", "b.pdf", "c.pdf", "deeper", "sub"])
    }

    /// `WatchedFolder.depth` is an unbounded `Int`. Nothing below 1 may read
    /// anything: the dangerous failure would be a zero or negative depth falling
    /// through to an unlimited walk of somebody's home folder.
    func testADepthBelowOneReadsNothing() throws {
        try write("a.pdf", in: root)
        try write("sub/b.pdf", in: root)

        XCTAssertTrue(names(depth: 0).isEmpty)
        XCTAssertTrue(names(depth: -1).isEmpty)
        XCTAssertTrue(names(depth: Int.min).isEmpty)
    }

    func testAnEnormousDepthIsJustTheWholeTree() throws {
        try write("one/two/three/c.pdf", in: root)
        XCTAssertEqual(names(depth: Int.max), names(depth: 4))
    }

    // MARK: - Names

    /// The names a Downloads folder actually collects. All of these are legal
    /// on APFS, and every one of them has to survive being read, planned and
    /// compared without the module deciding it has found a path.
    func testAwkwardNamesAreReadAsSingleFiles() throws {
        let awkward = ["two words.pdf", "отчёт.pdf", "🙂.pdf", "a\tb.pdf", "a.b.c.pdf",
                       "a-file-with-no-extension", "ALLCAPS.PDF", "trailing space .pdf"]
        for name in awkward { try write(name, in: root) }

        XCTAssertEqual(names(depth: 1), awkward.sorted(),
                       "a name was dropped, split or rewritten on the way in")
    }

    /// A leading dot is a hidden file and the enumerator skips it, so a rule
    /// never sees one. That is the safe direction and it is worth pinning: a
    /// file called `.pdf` — a name that is nothing but an extension — is
    /// otherwise the input that makes `deletingPathExtension` and
    /// `pathExtension` disagree with each other.
    func testHiddenFilesAreNeverOfferedToARule() throws {
        try write(".pdf", in: root)
        try write(".hidden.pdf", in: root)
        try write("visible.pdf", in: root)

        XCTAssertEqual(names(depth: 1), ["visible.pdf"])
    }

    /// An empty folder is no facts, not one fact about itself.
    func testAnEmptyFolderOffersNothing() {
        XCTAssertTrue(names(depth: 1).isEmpty)
    }

    /// A folder that is not there reads as empty rather than throwing or
    /// hanging — the folder a rule watches can be on a volume that went away
    /// between the sweep timer firing and the enumerator starting.
    func testAFolderThatIsGoneReadsAsEmpty() {
        XCTAssertTrue(reader.facts(in: root.appendingPathComponent("gone").path,
                                   depth: 1).isEmpty)
    }
}
