import XCTest
@testable import HelmRuntime

/// Files that name somebody's files are written at 0600, every time.
///
/// **The mode is not a property of the file, it is a property of each write.**
/// `.atomic` writes a temporary file and renames it over the target, so the mode
/// comes from the process umask on a fresh write and from the *replaced* file on
/// a rewrite. Measured in a plain process: 0644 either way. Get it wrong once in
/// a file holding an index of every filename on the volume and the privacy of
/// that list becomes an accident of the environment.
final class PrivateFileTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-private-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    func testAFreshWriteIsPrivate() throws {
        let url = directory.appendingPathComponent("fresh.json")
        PrivateFile.write(["a", "b"], to: url)
        XCTAssertEqual(try mode(of: url), 0o600)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)),
                       ["a", "b"])
    }

    /// The case the three hand-written copies existed for: a file that is
    /// already readable stays readable through an atomic rewrite unless the mode
    /// is set again.
    func testARewriteOverALooseFileIsMadePrivate() throws {
        let url = directory.appendingPathComponent("loose.json")
        FileManager.default.createFile(atPath: url.path, contents: Data("[]".utf8),
                                       attributes: [.posixPermissions: 0o644])
        XCTAssertEqual(try mode(of: url), 0o644)
        PrivateFile.write(["later"], to: url)
        XCTAssertEqual(try mode(of: url), 0o600)
    }

    func testRawDataIsWrittenTheSameWay() throws {
        let url = directory.appendingPathComponent("salt.bin")
        FileManager.default.createFile(atPath: url.path, contents: Data([0]),
                                       attributes: [.posixPermissions: 0o644])
        PrivateFile.write(Data([1, 2, 3]), to: url)
        XCTAssertEqual(try mode(of: url), 0o600)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }

    func testANewDirectoryIsPrivate() throws {
        let url = directory.appendingPathComponent("new/deeper")
        PrivateFile.directory(at: url)
        XCTAssertEqual(try mode(of: url), 0o700)
    }

    /// `attributes:` covers only the directories the call itself creates, so a
    /// looser one left by an earlier build would keep its mode for ever.
    func testAnExistingLooseDirectoryIsTightened() throws {
        let url = directory.appendingPathComponent("old")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(try mode(of: url), 0o755)
        PrivateFile.directory(at: url)
        XCTAssertEqual(try mode(of: url), 0o700)
    }

    /// A write that cannot happen is never a reason to fail the work that asked
    /// for it — these files are caches, journals and salts — so it reports
    /// rather than throws, and the caller decides.
    func testAWriteThatCannotHappenSaysSo() {
        let url = directory.appendingPathComponent("nowhere/at/all.json")
        XCTAssertFalse(PrivateFile.write(["x"], to: url))
        XCTAssertTrue(PrivateFile.write(["x"], to: directory.appendingPathComponent("fine.json")))
    }
}
