import Foundation
import HelmTestSupport
import XCTest

/// A read of the tree that could not open what it was asked for says so.
///
/// `swiftFiles(under:)` ends its walk with an empty list when the enumerator comes back nil. Measured on a
/// directory that is not there, on a plain file, on a mode-000 directory and on a mode-000 directory under a
/// readable one, the enumerator is never nil and the error handler of the walk is called, so each of the four
/// throws and the empty list is not reachable by any of them. The refusal rows for the walk assert that: no
/// list comes back, and the refusal carries the POSIX code of its cause. Beside them a walk that can be
/// opened returns its one `.swift` file.
///
/// The next rows read the tree that is there: the walk of `Tests/Support`, the root, and the standing
/// documents against a second scan of the hub's links. The rows for `root(above:)` start from scratch
/// directories, with no manifest above, with one above, with two, and in the manifest's own directory, and
/// from inside this tree; each asserts the directory it answers, or that the refusal names where it started.
/// The rows for `StandingDocuments.all(hub:)` give it a hub that is not there, which records one failure at
/// the line that asked and lists the four core documents, and a hub that is, which records nothing and lists
/// the pages that hub links. A failure is caught by overriding `record` between `startListening` and
/// `stopListening`, as `AGateNobodyArrivedAtFailsTests` does.
final class AReadOfTheTreeThatFindsNothingSaysSoTests: XCTestCase {

    private let heard = HeardFailures()

    override func record(_ issue: XCTIssue) {
        guard !heard.take(issue) else { return }
        super.record(issue)
    }

    // MARK: - swiftFiles(under:)

    func testADirectoryThatIsNotThereIsRefusedNotEmptied() throws {
        let missing = try fromTheRoot(scratchDirectory("tree-missing").appendingPathComponent("no-such-directory"))

        let outcome = walk(missing)

        XCTAssertNil(outcome.files, "a directory that is not there was walked and returned \(String(describing: outcome.files))")
        XCTAssertTrue(outcome.refusal?.contains("NSPOSIXErrorDomain Code=2 ") ?? false, "the refusal does not name the cause: \(String(describing: outcome.refusal))")
    }

    func testAPlainFileIsRefusedNotEmptied() throws {
        let scratch = scratchDirectory("tree-plain")
        let file = try write("plain.txt", in: scratch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the plain file was not made")

        let outcome = walk(try fromTheRoot(file))

        XCTAssertNil(outcome.files, "a plain file was walked and returned \(String(describing: outcome.files))")
        XCTAssertTrue(outcome.refusal?.contains("NSPOSIXErrorDomain Code=20 ") ?? false, "the refusal does not name the cause: \(String(describing: outcome.refusal))")
    }

    func testADirectoryWithNoPermissionIsRefusedNotEmptied() throws {
        let scratch = scratchDirectory("tree-locked")
        let locked = scratch.appendingPathComponent("locked")
        try write("locked/A.swift", in: scratch)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertFalse(FileManager.default.isReadableFile(atPath: locked.path), "the directory is still readable, so this row is not about a refused one")

        let outcome = walk(try fromTheRoot(locked))

        XCTAssertNil(outcome.files, "a mode-000 directory was walked and returned \(String(describing: outcome.files))")
        XCTAssertTrue(outcome.refusal?.contains("NSPOSIXErrorDomain Code=13 ") ?? false, "the refusal does not name the cause: \(String(describing: outcome.refusal))")
    }

    func testADirectoryUnderAReadableOneWithNoPermissionIsRefusedNotLeftOut() throws {
        let scratch = scratchDirectory("tree-inner")
        try write("outer/B.swift", in: scratch)
        try write("outer/inner/C.swift", in: scratch)
        let inner = scratch.appendingPathComponent("outer/inner")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: inner.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inner.path) }
        XCTAssertFalse(FileManager.default.isReadableFile(atPath: inner.path), "the inner directory is still readable")

        let outcome = walk(try fromTheRoot(scratch.appendingPathComponent("outer")))

        XCTAssertNil(outcome.files, "a walk past a mode-000 subdirectory returned \(String(describing: outcome.files))")
        XCTAssertTrue(outcome.refusal?.contains("NSPOSIXErrorDomain Code=13 ") ?? false, "the refusal does not name the cause: \(String(describing: outcome.refusal))")
    }

    func testADirectoryThatCanBeOpenedReturnsItsFiles() throws {
        let scratch = scratchDirectory("tree-fine")
        try write("fine/D.swift", in: scratch)
        try write("fine/notes.txt", in: scratch)

        let outcome = walk(try fromTheRoot(scratch.appendingPathComponent("fine")))

        XCTAssertNil(outcome.refusal, "a readable directory was refused")
        XCTAssertEqual(outcome.files?.count, 1, "only the swift file is listed: \(String(describing: outcome.files))")
        XCTAssertTrue(outcome.files?.first?.hasSuffix("D.swift") ?? false, "\(String(describing: outcome.files))")
    }

    func testTheSupportFolderOfTheRepositoryIsListedFromTheRoot() throws {
        let files = try RepoSource.swiftFiles(under: "Tests/Support")

        XCTAssertTrue(files.contains("Tests/Support/RepoSource.swift"), "the walk of Tests/Support does not list RepoSource.swift: \(files.prefix(5))")
        XCTAssertTrue(files.allSatisfy { $0.hasPrefix("Tests/Support/") }, "a path is not repo-relative: \(files.filter { !$0.hasPrefix("Tests/Support/") })")
        XCTAssertGreaterThan(files.count, 10)
    }

    // MARK: - root and the standing documents

    func testTheRootHoldsThePackageManifest() {
        let root = RepoSource.root

        // No assertion that the root is not "/": the process stops with the failure's text before `root` could
        // answer it, so no run reaches this line with that answer.
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path), "\(root.path) holds no Package.swift")
    }

    // MARK: - root(above:)

    func testAScratchDirectoryWithNoManifestAboveItIsRefusedAndTheRefusalNamesWhereItStarted() throws {
        let scratch = scratchDirectory("root-none")
        let start = scratch.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: start, withIntermediateDirectories: true)
        XCTAssertEqual(manifests(atOrAbove: start), [], "a Package.swift lies at or above the scratch directory, so this row is not about a start with none above it")

        var answered: URL?
        var refusal: String?
        do {
            answered = try RepoSource.root(above: start)
        } catch {
            refusal = "\(error)"
        }

        XCTAssertNil(answered, "root(above:) answered \(String(describing: answered?.path)) for a start with no manifest above it")
        XCTAssertTrue(refusal?.contains(start.path) ?? false, "the refusal does not name where it started, \(start.path): \(String(describing: refusal))")
    }

    func testAScratchParentHoldingAManifestIsAnsweredFromANestedStart() throws {
        let scratch = scratchDirectory("root-parent")
        try write("Package.swift", in: scratch)
        let start = scratch.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: start, withIntermediateDirectories: true)
        XCTAssertEqual(manifests(atOrAbove: start), [scratch.path], "the scratch parent's manifest is not the only one at or above the start")

        let found = try RepoSource.root(above: start)

        XCTAssertEqual(found.path, scratch.path)
    }

    func testTheNearerOfTwoManifestsWins() throws {
        let scratch = scratchDirectory("root-two")
        try write("Package.swift", in: scratch)
        try write("inner/Package.swift", in: scratch)
        let inner = scratch.appendingPathComponent("inner")
        let start = inner.appendingPathComponent("deep/deeper")
        try FileManager.default.createDirectory(at: start, withIntermediateDirectories: true)
        XCTAssertEqual(manifests(atOrAbove: start), [inner.path, scratch.path], "the start does not have two manifests above it, the nearer first")

        let found = try RepoSource.root(above: start)

        XCTAssertEqual(found.path, inner.path, "the farther manifest, \(scratch.path), was answered")
    }

    func testAStartInTheManifestsOwnDirectoryAnswersIt() throws {
        let scratch = scratchDirectory("root-own")
        try write("Package.swift", in: scratch)
        try write("above/Package.swift", in: scratch)
        let own = scratch.appendingPathComponent("above")
        XCTAssertEqual(manifests(atOrAbove: own), [own.path, scratch.path], "the start does not hold a manifest with another above it")

        let found = try RepoSource.root(above: own)

        XCTAssertEqual(found.path, own.path)
    }

    func testAStartInsideThisTreeAnswersTheRoot() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let support = RepoSource.root.appendingPathComponent("Tests/Support")
        XCTAssertTrue(FileManager.default.fileExists(atPath: RepoSource.root.appendingPathComponent("Package.swift").path), "the root holds no Package.swift")
        XCTAssertNotEqual(here.path, RepoSource.root.path, "this file's directory is the root, so the start is not nested")
        XCTAssertNotEqual(support.path, RepoSource.root.path)

        XCTAssertEqual(try RepoSource.root(above: here).path, RepoSource.root.path)
        XCTAssertEqual(try RepoSource.root(above: support).path, RepoSource.root.path)
    }

    // MARK: - StandingDocuments.all(hub:)

    func testAHubThatIsNotThereRecordsOneFailureAtTheLineThatAskedAndStillListsTheFour() {
        let missing = "no-such-hub-\(UUID().uuidString).md"
        XCTAssertFalse(FileManager.default.fileExists(atPath: RepoSource.root.appendingPathComponent(missing).path), "the hub is there, so this row is not about a hub that is not")

        var askedAt: UInt = 0
        heard.startListening()
        askedAt = #line; let all = StandingDocuments.all(hub: missing)
        let failures = heard.stopListening()

        let here = URL(fileURLWithPath: #filePath).standardized.path
        XCTAssertEqual(failures.count, 1, "the failures were \(failures.map { "\($0.path):\($0.line) \($0.text)" }), and one is wanted")
        XCTAssertTrue(failures.contains(HeardFailure(path: here, line: Int(askedAt))),
                      "the failures were \(failures.map { "\($0.path):\($0.line)" }), and one is wanted at this file, line \(askedAt)")
        XCTAssertTrue(failures.first?.text.contains(missing) ?? false, "the failure does not name the hub: \(String(describing: failures.first?.text))")
        XCTAssertEqual(all, ["ARCHITECTURE.md", "CLAUDE.md", "README.md", "CHANGELOG.md"])
    }

    func testTheHubItselfIsReadWithoutAFailureAndAnswersAsTheDefaultDoes() {
        heard.startListening()
        let named = StandingDocuments.all(hub: "ARCHITECTURE.md")
        let byDefault = StandingDocuments.all()
        let failures = heard.stopListening()

        XCTAssertGreaterThan(named.count, 4, "the hub links no pages, so this row would pass for a hub nobody read")
        XCTAssertEqual(failures.map { "\($0.path):\($0.line) \($0.text)" }, [], "a readable hub recorded a failure")
        XCTAssertEqual(named, byDefault)
    }

    func testAHubInAScratchDirectoryListsThePagesItLinksAfterTheFour() throws {
        let scratch = scratchDirectory("hub-own")
        let hub = scratch.appendingPathComponent("hub.md")
        try "# Hub\n- [Alpha](Architecture/Alpha.md)\n- [Beta](Architecture/Beta.md)\n- [Other](Other/Gamma.md)\n"
            .write(to: hub, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hub.path), "the hub was not made")
        let relative = try fromTheRoot(hub)

        heard.startListening()
        let all = StandingDocuments.all(hub: relative)
        let failures = heard.stopListening()

        XCTAssertEqual(failures.map { "\($0.path):\($0.line) \($0.text)" }, [], "a readable hub recorded a failure")
        XCTAssertEqual(all, ["ARCHITECTURE.md", "CLAUDE.md", "README.md", "CHANGELOG.md",
                             "Architecture/Alpha.md", "Architecture/Beta.md"],
                       "the list is not the four and the two pages this hub links")
    }

    func testTheStandingDocumentsAreTheCoreFourAndTheTreesPagesInLinkOrder() throws {
        let hub = try RepoSource.text(of: "ARCHITECTURE.md")
        var linked: [String] = []
        for part in hub.components(separatedBy: "](Architecture/").dropFirst() {
            guard let end = part.firstIndex(of: ")") else { continue }
            let name = String(part[..<end])
            guard name.hasSuffix(".md"), name.dropLast(3).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { continue }
            linked.append("Architecture/" + name)
        }
        XCTAssertGreaterThan(linked.count, 5, "this scan found \(linked.count) pages linked from the hub, too few to tell a hub that was read from one nobody read")

        let all = StandingDocuments.all()

        XCTAssertEqual(Array(all.prefix(4)), ["ARCHITECTURE.md", "CLAUDE.md", "README.md", "CHANGELOG.md"])
        XCTAssertEqual(Array(all.dropFirst(4)), linked)
        for page in linked {
            XCTAssertTrue(FileManager.default.fileExists(atPath: RepoSource.root.appendingPathComponent(page).path), "\(page) is linked and not on disk")
        }
    }

    // MARK: - Helpers

    /// The directories at or above `start`, nearest first, that hold a `Package.swift`, asked of the file
    /// system directly and up to the top of the disk, which is asked last.
    private func manifests(atOrAbove start: URL) -> [String] {
        var found: [String] = []
        var path = start.path
        while path != "/" && !path.isEmpty {
            if FileManager.default.fileExists(atPath: path + "/Package.swift") { found.append(path) }
            path = (path as NSString).deletingLastPathComponent
        }
        if FileManager.default.fileExists(atPath: "/Package.swift") { found.append("/") }
        return found
    }

    /// What `swiftFiles(under:)` answered: the files, or the text of its refusal, never both.
    private struct Outcome {
        let files: [String]?
        let refusal: String?
    }

    private func walk(_ relative: String) -> Outcome {
        do {
            return Outcome(files: try RepoSource.swiftFiles(under: relative), refusal: nil)
        } catch {
            return Outcome(files: nil, refusal: "\(error)")
        }
    }

    /// `url` as a path from the root, climbing out of the repository first, because the reader takes
    /// a path from the root and a scratch directory is not under it.
    private func fromTheRoot(_ url: URL) throws -> String {
        let climb = String(repeating: "../", count: RepoSource.root.pathComponents.count - 1)
        let target = String(url.resolvingSymlinksInPath().path.dropFirst())
        let relative = climb + target
        let reached = RepoSource.root.appendingPathComponent(relative).standardized.path
        XCTAssertEqual(reached, url.resolvingSymlinksInPath().path, "the path from the root does not reach the scratch folder")
        return relative
    }
}
