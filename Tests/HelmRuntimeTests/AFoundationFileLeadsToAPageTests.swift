import HelmTestSupport
import XCTest

/// A Swift file of `corpus` at or over `threshold` bytes is named by a page, or its text
/// holds a pointer at the architecture document, or it is on the list below.
///
/// **Why this is a test.** From a file of the tree an agent cannot always find the page
/// that explains it. The hub's sentence under the map sends a file that is not a
/// module's to the heading its doc comment points at, else to what `command grep -rlw`
/// prints for the file's name less its extension over the hub and the pages, else to the
/// page of the deepest row its path is under. A large file reached by neither of the
/// first two is left with the page of its row, which does not name it, and nothing else
/// in the suite counts it.
///
/// **What is measured.** The `.swift` files under `Sources/HelmContract`,
/// `Sources/HelmRuntime` and `Sources/HelmUI`, recursively, of `threshold` bytes or more
/// (UTF-8 bytes of the text). A module's file goes to its module's page and is outside
/// this; `Sources/HelmApp` is the executable and `Sources/HelmLaunch` holds no Swift. The
/// directories directly under `Sources` must equal those of `corpus` plus those of
/// `leftOut`, each with its reason, so a new directory is not silently outside.
///
/// **A page names a file** when the stem (the file name less its extension) stands as a
/// whole word, case included, in the hub or in a page the hub links: the same words
/// `command grep -rlw` takes, so the sentence and this check read one thing. `CLAUDE.md`
/// and `README.md` are not read. A basename that another `.swift` under `Sources` or
/// `Tests` also carries is not an address, so for such a file the stem does not count and
/// only the path from the root names it.
///
/// **A pointer leaves a file** when its text, in a comment or out of one, holds a pointer
/// that names `ARCHITECTURE` before the section sign, read by the sections guard's
/// `Parser.named(in:)`. That reader turns a line break into a space and leaves the `///`
/// of the next line where it stood, so a pointer whose document name ends one doc-comment
/// line and whose sign opens the next is not read and its file is reported: the difference
/// fails closed. Whether the pointer's heading exists is the code guard's, not this one's.
///
/// **The list.** `withoutAWayUp` holds paths from the root, sorted, and no byte counts: the
/// check reads a listed file's size from the tree. A file at or over `threshold` that no
/// page names and no pointer leaves is red unless it is listed. A listed file that is now
/// named, now carries a pointer, is under the threshold or is gone is red until it comes
/// off. The list takes no new entry, and no row can hold that: a row sees the list as it
/// stands, so an unreached file added with its entry is green, and the order is this
/// comment's alone.
///
/// **What holds what.** The tree row holds the list against the tree: an unreached file
/// taken off it, or a listed file that a page names, turns it red. It does not hold the
/// list's length (an unreached file added with its entry is green), nor the edge of the
/// threshold or the whole-word reading, because no file of the tree is exactly `threshold`
/// bytes and no listed file's stem stands inside a longer word of a page, so the tree row
/// reads the same with `>` for `>=` or with the word boundaries dropped. Those two stand
/// on the fixture rows `testAFileAtTheThresholdAndUnnamedIsListedAndOneByteUnderIsNot`,
/// `testTheSizeIsBytesAndNotCharacters` and
/// `testAStemAsAWholeWordNamesTheFileAndInsideALongerWordDoesNot`.
final class AFoundationFileLeadsToAPageTests: XCTestCase {

    /// Bytes at which a file is measured.
    static let threshold = 8_192

    /// The foundation directories whose files are measured.
    static let corpus = ["Sources/HelmContract", "Sources/HelmRuntime", "Sources/HelmUI"]

    /// The directories directly under `Sources` that are not measured, with the reason.
    static let leftOut = [
        "HelmApp": "the executable, not a foundation target",
        "HelmLaunch": "no Swift",
        "Modules": "a module's file goes to its module's page",
    ]

    /// Files of `corpus` at or over `threshold` that no page names and no pointer leaves.
    private static let withoutAWayUp: [String] = [
        "Sources/HelmUI/DesignSystem/HelmExplainer.swift",
        "Sources/HelmUI/DesignSystem/HotkeyRecorder.swift",
        "Sources/HelmUI/DesignSystem/MenuBarIcon.swift",
        "Sources/HelmUI/DesignSystem/PermissionNote.swift",
        "Sources/HelmUI/DesignSystem/RemovalOutcome.swift",
        "Sources/HelmUI/DesignSystem/ShellGlyph.swift",
        "Sources/HelmUI/Welcome/WelcomeView.swift",
    ]

    // MARK: - The reading, over text and names only

    /// What the pages and the file's own text say about one file.
    struct Reading: Equatable {
        let path: String
        let bytes: Int
        /// The first document that names the file, by its path from the root.
        let namedBy: String?
        /// The text holds a pointer that names `ARCHITECTURE`.
        let pointer: Bool

        var stem: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

        func unreached(threshold: Int) -> Bool { bytes >= threshold && namedBy == nil && !pointer }
    }

    /// One reading for each file. `sharedNames` are the basenames more than one file of
    /// the tree carries; such a file is named only by its path from the root.
    static func readings(files: [(path: String, text: String)], documents: [(name: String, text: String)],
                         sharedNames: Set<String>) -> [Reading] {
        files.map { file in
            let base = (file.path as NSString).lastPathComponent
            let stem = (base as NSString).deletingPathExtension
            let namedBy: String?
            if sharedNames.contains(base) {
                namedBy = documents.first { $0.text.contains(file.path) }?.name
            } else {
                let word = try! NSRegularExpression(
                    pattern: "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: stem)
                        + "(?![A-Za-z0-9_])")
                namedBy = documents.first {
                    word.firstMatch(in: $0.text, range: NSRange($0.text.startIndex..., in: $0.text)) != nil
                }?.name
            }
            let pointer = EverySectionNamedInTheDocumentsExistsTests.Parser.named(in: file.text)
                .contains { $0.document == "ARCHITECTURE" }
            return Reading(path: file.path, bytes: file.text.utf8.count, namedBy: namedBy, pointer: pointer)
        }
    }

    /// The paths at or over `threshold` that no document names and no pointer leaves.
    static func filesWithoutAWayUp(files: [(path: String, text: String)], documents: [String],
                                   sharedNames: Set<String>, threshold: Int) -> [String] {
        readings(files: files, documents: documents.map { (name: "a document", text: $0) },
                 sharedNames: sharedNames)
            .filter { $0.unreached(threshold: threshold) }
            .map(\.path)
    }

    /// What the list gets wrong of the readings, one line each: a measured file that is
    /// unreached and not listed; a listed file that is gone, under the threshold, named or
    /// carrying a pointer; a list that is not sorted or holds a path twice.
    static func listDefects(readings: [Reading], listed: [String], threshold: Int) -> [String] {
        var defects: [String] = []
        for reading in readings.sorted(by: { $0.path < $1.path })
        where reading.unreached(threshold: threshold) && !listed.contains(reading.path) {
            defects.append("\(reading.path): \(reading.bytes) B, no page names \(reading.stem) and no pointer "
                + "leaves it — name it on the page that explains it or give its doc comment a pointer; "
                + "the list takes no new entry")
        }
        for path in listed.sorted() {
            guard let reading = readings.first(where: { $0.path == path }) else {
                defects.append("\(path): gone — take it off the list")
                continue
            }
            if reading.bytes < threshold {
                defects.append("\(path): \(reading.bytes) B, under \(threshold) — take it off the list")
            } else if let page = reading.namedBy {
                defects.append("\(path): named by \(page) — take it off the list")
            } else if reading.pointer {
                defects.append("\(path): carries a pointer — take it off the list")
            }
        }
        if listed != listed.sorted() || Set(listed).count != listed.count {
            defects.append("the list is not sorted or holds a path twice")
        }
        return defects
    }

    /// What the directories directly under `Sources` get wrong of `corpus` and `leftOut`:
    /// one neither measured nor left out, one named that is not there.
    static func directoryDefects(directories: [String], corpus: [String], leftOut: [String]) -> [String] {
        let named = Set(corpus + leftOut)
        var defects: [String] = []
        for name in Set(directories).subtracting(named).sorted() {
            defects.append("Sources/\(name) is neither measured nor left out with a reason")
        }
        for name in named.subtracting(directories).sorted() {
            defects.append("Sources/\(name) is named here and is not a directory of the tree")
        }
        return defects
    }

    // MARK: - The tree

    func testEveryLargeFoundationFileHasAWayUp() throws {
        let hub = try RepoSource.text(of: "ARCHITECTURE.md")
        let linked = StandingDocuments.linkedPages(in: hub)
        XCTAssertFalse(linked.isEmpty, "the hub links no page — every file would read as unnamed")
        var documents = [(name: "ARCHITECTURE.md", text: hub)]
        for page in linked { documents.append((name: page, text: try RepoSource.text(of: page))) }

        var files: [(path: String, text: String)] = []
        for directory in Self.corpus {
            var isDirectory: ObjCBool = false
            let full = RepoSource.root.appendingPathComponent(directory).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory)
                          && isDirectory.boolValue, "\(directory) is not a directory of the tree")
            let found = try RepoSource.swiftFiles(under: directory)
            XCTAssertFalse(found.isEmpty, "\(directory) gave no Swift file — nothing of it was measured")
            for path in found { files.append((path: path, text: try RepoSource.text(of: path))) }
        }

        var seen: [String: Int] = [:]
        for top in ["Sources", "Tests"] {
            for path in try RepoSource.swiftFiles(under: top) {
                seen[(path as NSString).lastPathComponent, default: 0] += 1
            }
        }
        let shared = Set(seen.filter { $0.value > 1 }.keys)

        let readings = Self.readings(files: files, documents: documents, sharedNames: shared)
        let large = readings.filter { $0.bytes >= Self.threshold }
        let named = large.filter { $0.namedBy != nil }
        let byPointerAlone = large.filter { $0.namedBy == nil && $0.pointer }
        XCTAssertFalse(large.isEmpty, "no file reached \(Self.threshold) B — the threshold measured nothing")
        print("foundation files: walked \(readings.count), at or over \(Self.threshold) B \(large.count), "
              + "named by a page \(named.count), by a pointer alone \(byPointerAlone.count), "
              + "listed \(Self.withoutAWayUp.count)")

        let defects = Self.listDefects(readings: readings, listed: Self.withoutAWayUp,
                                       threshold: Self.threshold)
        XCTAssertTrue(defects.isEmpty,
                      "\(defects.count) foundation file(s) without a way up:\n\(defects.joined(separator: "\n"))")
    }

    func testEveryDirectoryUnderSourcesIsMeasuredOrLeftOutWithAReason() throws {
        let directories = try TheMapNamesRealDirectoriesTests.directories(under: "Sources")
        XCTAssertFalse(directories.isEmpty, "Sources gave no directory — nothing was compared")
        let corpusNames = Self.corpus.map { ($0 as NSString).lastPathComponent }
        let defects = Self.directoryDefects(directories: directories, corpus: corpusNames,
                                            leftOut: Array(Self.leftOut.keys))
        XCTAssertTrue(defects.isEmpty, defects.joined(separator: "\n"))
        XCTAssertEqual(try RepoSource.swiftFiles(under: "Sources/HelmLaunch"), [],
                       "`HelmLaunch` is left out as holding no Swift, and it holds some")
    }

    // MARK: - Fixtures

    private static func file(_ path: String, bytes: Int, head: String = "") -> (path: String, text: String) {
        let text = head + String(repeating: "a", count: max(0, bytes - head.utf8.count))
        return (path: path, text: text)
    }

    private static func without(_ files: [(path: String, text: String)], documents: [String] = [],
                                shared: Set<String> = []) -> [String] {
        filesWithoutAWayUp(files: files, documents: documents, sharedNames: shared, threshold: threshold)
    }

    func testAFileAtTheThresholdAndUnnamedIsListedAndOneByteUnderIsNot() {
        let at = Self.file("Sources/HelmUI/Foo.swift", bytes: 8_192)
        let under = Self.file("Sources/HelmUI/Foo.swift", bytes: 8_191)
        XCTAssertEqual(at.text.utf8.count, 8_192)
        XCTAssertEqual(under.text.utf8.count, 8_191)
        XCTAssertEqual(Self.without([at]), ["Sources/HelmUI/Foo.swift"])
        XCTAssertEqual(Self.without([under]), [])
    }

    func testTheSizeIsBytesAndNotCharacters() {
        // 4,096 two-byte characters are 8,192 bytes and 4,096 characters.
        let text = String(repeating: "\u{E9}", count: 4_096)
        XCTAssertEqual(text.utf8.count, 8_192)
        XCTAssertEqual(Self.without([(path: "Sources/HelmUI/Foo.swift", text: text)]),
                       ["Sources/HelmUI/Foo.swift"])
    }

    func testAStemAsAWholeWordNamesTheFileAndInsideALongerWordDoesNot() {
        let big = [Self.file("Sources/HelmUI/Foo.swift", bytes: 9_000)]
        XCTAssertEqual(Self.without(big, documents: ["the type Foo does it"]), [])
        XCTAssertEqual(Self.without(big, documents: ["`Foo`."]), [])
        XCTAssertEqual(Self.without(big, documents: ["Sources/HelmUI/Foo.swift"]), [], "a path ends in the stem")
        XCTAssertEqual(Self.without(big, documents: ["FooBar"]), big.map(\.path))
        XCTAssertEqual(Self.without(big, documents: ["BarFoo"]), big.map(\.path))
        XCTAssertEqual(Self.without(big, documents: ["Foo2 and Foo_x"]), big.map(\.path))
        XCTAssertEqual(Self.without(big, documents: ["foo"]), big.map(\.path), "case counts")
    }

    func testAPointerToTheArchitectureDocumentLeavesTheFileAndOneToTheOtherDoesNot() {
        let named = "/// ARCHITECTURE.md \u{A7} Targets.\n"
        let other = "/// CLAUDE.md \u{A7} Commands.\n"
        let wrapped = "/// ARCHITECTURE.md\n/// \u{A7} Targets.\n"
        let none = "/// See the targets page.\n"
        XCTAssertEqual(Self.without([Self.file("Sources/HelmUI/A.swift", bytes: 9_000, head: named)]), [])
        XCTAssertEqual(Self.without([Self.file("Sources/HelmUI/B.swift", bytes: 9_000, head: other)]),
                       ["Sources/HelmUI/B.swift"])
        XCTAssertEqual(Self.without([Self.file("Sources/HelmUI/C.swift", bytes: 9_000, head: none)]),
                       ["Sources/HelmUI/C.swift"])
        // The name and the sign split by a doc-comment break are not read: the file is reported.
        XCTAssertEqual(Self.without([Self.file("Sources/HelmUI/D.swift", bytes: 9_000, head: wrapped)]),
                       ["Sources/HelmUI/D.swift"])
    }

    func testASharedBasenameIsNamedByItsPathAndNotByItsStem() {
        let shared: Set<String> = ["Foo.swift"]
        let big = [Self.file("Sources/HelmUI/Foo.swift", bytes: 9_000)]
        XCTAssertEqual(Self.without(big, documents: ["the type Foo"], shared: shared), big.map(\.path))
        XCTAssertEqual(Self.without(big, documents: ["Sources/HelmUI/Foo.swift"], shared: shared), [])
        XCTAssertEqual(Self.without(big, documents: ["Sources/HelmRuntime/Foo.swift"], shared: shared),
                       big.map(\.path), "the other file's path does not name this one")
        XCTAssertEqual(Self.without(big, documents: ["the type Foo"], shared: []), [], "unshared, the stem counts")
    }

    func testTheListIsRedForAFileUnlistedAndForAnEntryThatIsStale() {
        func reading(_ path: String, _ bytes: Int, named: String? = nil, pointer: Bool = false)
            -> AFoundationFileLeadsToAPageTests.Reading {
            .init(path: path, bytes: bytes, namedBy: named, pointer: pointer)
        }
        let a = reading("Sources/HelmUI/A.swift", 9_000)
        let a2 = reading("Sources/HelmUI/A2.swift", 9_000)
        let b = reading("Sources/HelmUI/B.swift", 9_000, named: "Architecture/Targets.md")
        let c = reading("Sources/HelmUI/C.swift", 9_000, pointer: true)
        let d = reading("Sources/HelmUI/D.swift", 100)
        let all = [a, a2, b, c, d]
        func defects(_ listed: [String]) -> [String] {
            Self.listDefects(readings: all, listed: listed, threshold: 8_192)
        }

        XCTAssertEqual(defects([a.path, a2.path]), [])
        let unlisted = defects([a.path])
        XCTAssertEqual(unlisted.count, 1, "\(unlisted)")
        XCTAssertTrue(unlisted.first?.contains("Sources/HelmUI/A2.swift: 9000 B, no page names A2") ?? false)
        XCTAssertTrue(unlisted.first?.contains("the list takes no new entry") ?? false)

        let named = defects([a.path, a2.path, b.path])
        XCTAssertEqual(named.count, 1)
        XCTAssertTrue(named.first?.contains("named by Architecture/Targets.md — take it off the list") ?? false)
        let pointed = defects([a.path, a2.path, c.path])
        XCTAssertEqual(pointed.count, 1)
        XCTAssertTrue(pointed.first?.contains("carries a pointer — take it off the list") ?? false)
        let small = defects([a.path, a2.path, d.path])
        XCTAssertEqual(small.count, 1)
        XCTAssertTrue(small.first?.contains("100 B, under 8192 — take it off the list") ?? false)
        let gone = defects([a.path, a2.path, "Sources/HelmUI/Z.swift"])
        XCTAssertEqual(gone.count, 1)
        XCTAssertTrue(gone.first?.contains("gone — take it off the list") ?? false)

        XCTAssertEqual(defects([a2.path, a.path]).count, 1, "unsorted")
        XCTAssertEqual(defects([a.path, a.path, a2.path]).count, 1, "twice")
        XCTAssertEqual(Self.listDefects(readings: [], listed: [], threshold: 8_192), [], "nothing measured, nothing listed")
    }

    func testADirectoryUnderSourcesNeitherMeasuredNorLeftOutIsRed() {
        let corpus = ["HelmContract", "HelmRuntime", "HelmUI"]
        let leftOut = ["HelmApp", "HelmLaunch", "Modules"]
        XCTAssertEqual(Self.directoryDefects(directories: corpus + leftOut, corpus: corpus, leftOut: leftOut), [])
        let added = Self.directoryDefects(directories: corpus + leftOut + ["HelmNew"], corpus: corpus, leftOut: leftOut)
        XCTAssertEqual(added.count, 1)
        XCTAssertTrue(added.first?.contains("Sources/HelmNew") ?? false)
        let removed = Self.directoryDefects(directories: corpus + ["HelmApp", "Modules"], corpus: corpus, leftOut: leftOut)
        XCTAssertEqual(removed.count, 1)
        XCTAssertTrue(removed.first?.contains("Sources/HelmLaunch") ?? false)
    }
}
