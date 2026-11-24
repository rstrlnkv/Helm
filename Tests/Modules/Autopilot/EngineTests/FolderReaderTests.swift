import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The fixture both reader classes below stand on: a scratch folder and the
/// reader over it.
class FolderReaderRig: XCTestCase {

    fileprivate var root: URL!
    fileprivate let reader = FolderReader()

    override func setUpWithError() throws {
        root = scratchDirectory("reader")
    }

    fileprivate func names(depth: Int) -> [String] {
        reader.reading(in: root.path, depth: depth).files.map(\.name).sorted()
    }
}

/// What a rule is offered, and what it is not.
///
/// `FolderReader` is the only place a file becomes `FileFacts`, so it is the
/// only place a rule can be handed something it has no business seeing — the
/// insides of an app bundle, a file three levels down in a folder set to one.
/// Everything asserted here is about the *shape* of what comes back: which
/// names, at which levels. Sizes and dates come off the disk and are not this
/// module's to promise.
final class FolderReaderTests: FolderReaderRig {

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

        let facts = reader.reading(in: root.path, depth: 9).files
        for package in facts.filter({ $0.name.contains(".") && $0.name != "plain.txt" }) {
            XCTAssertFalse(package.isDirectory,
                           "\(package.name) is offered as a folder, so a folder rule will act on it")
            XCTAssertNotEqual(package.kind, .folder,
                              "\(package.name) is offered as a folder, so a folder rule will act on it")
        }
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

    // MARK: - What is weighed

    /// The only reader of `bytes` refuses a directory outright
    /// (`RuleMatcher`'s `.size` guard), so walking a plain folder for its
    /// weight is work computed and thrown away — measured at 33× the cost of
    /// the whole read on an ordinary tree. A package must keep its walk: it
    /// passes that guard by design, and a zero there once meant «smaller than
    /// 1 MB → Trash» matched every application in the folder
    /// (`PackageFactsTests`).
    ///
    /// Asked through the reader's own seam rather than timed: the assertion is
    /// that the question is never put, not that it is answered quickly.
    func testAPlainFolderIsNotWeighedAndWeighsNothing() throws {
        try write("sub/inner.bin", in: root)
        try write("Thing.app/Contents/MacOS/Thing", in: root)
        try write("plain.txt", in: root)

        let scale = Scale()
        let reader = FolderReader(weigh: { url in scale.weigh(url.lastPathComponent) })
        let facts = reader.reading(in: root.path, depth: 2).files

        // First that the read happened at all, so an empty answer cannot buy
        // the absence asserted below.
        XCTAssertEqual(facts.map(\.name).sorted(),
                       ["Thing.app", "inner.bin", "plain.txt", "sub"])
        XCTAssertFalse(scale.weighed.contains("sub"),
                       "a plain folder was weighed for a number no rule can read")
        // The weights that must survive, read back through the same seam so a
        // reader that stopped weighing everything cannot pass.
        XCTAssertEqual(facts.first { $0.name == "sub" }?.bytes, 0)
        XCTAssertEqual(facts.first { $0.name == "Thing.app" }?.bytes, 7)
        XCTAssertEqual(facts.first { $0.name == "plain.txt" }?.bytes, 7)
        XCTAssertEqual(facts.first { $0.name == "inner.bin" }?.bytes, 7)
    }

    /// The watcher's single-file read takes the same rule: it is handed
    /// directories too — a sort rule's own buckets arrive as FSEvents.
    func testTheWatchersReadDoesNotWeighAPlainFolderEither() throws {
        try write("bucket/inner.bin", in: root)

        let scale = Scale()
        let reader = FolderReader(weigh: { url in scale.weigh(url.lastPathComponent) })
        let facts = reader.facts(of: root.appendingPathComponent("bucket"))

        XCTAssertEqual(facts?.name, "bucket", "the folder was not read at all")
        XCTAssertEqual(facts?.bytes, 0)
        XCTAssertTrue(scale.weighed.isEmpty)
    }

    /// What the reader's `weigh` answers, and which names it was asked about.
    private final class Scale: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        var weighed: [String] { lock.withLock { names } }
        func weigh(_ name: String) -> Int {
            lock.withLock { names.append(name) }
            return 7
        }
    }
}
