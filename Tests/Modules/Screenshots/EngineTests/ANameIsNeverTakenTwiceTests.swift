import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A screenshot never replaces a file.** Two captures in one second share a
/// name, and the answer is "(1)", not an overwrite. The real writer, on a real
/// folder: `Data.write(options: .atomic)` is a rename over whatever is there,
/// which is exactly how the second capture would eat the first.
final class ANameIsNeverTakenTwiceTests: XCTestCase {

    private let base = "Screenshot 2026-09-30 at 14.02.11"

    func testATakenNameGoesOnCounting() throws {
        let folder = scratchDirectory("shots-names")
        let writer = FileShotWriter()
        let first = writer.write(Data("one".utf8), into: folder, base: base, pathExtension: "png")
        let second = writer.write(Data("two".utf8), into: folder, base: base, pathExtension: "png")
        let third = writer.write(Data("three".utf8), into: folder, base: base, pathExtension: "png")

        XCTAssertEqual(first.url, folder.appendingPathComponent("\(base).png"))
        XCTAssertEqual(second.url, folder.appendingPathComponent("\(base) (1).png"))
        XCTAssertEqual(third.url, folder.appendingPathComponent("\(base) (2).png"))
    }

    func testAPreExistingFileKeepsEveryByte() throws {
        let folder = scratchDirectory("shots-names-bytes")
        let original = folder.appendingPathComponent("\(base).png")
        let precious = Data("the picture somebody took a second ago".utf8)
        try precious.write(to: original)

        let result = FileShotWriter().write(Data("the new one".utf8), into: folder, base: base, pathExtension: "png")

        XCTAssertEqual(try Data(contentsOf: original), precious, "the writer replaced a file that was there")
        XCTAssertEqual(result.url, folder.appendingPathComponent("\(base) (1).png"))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("\(base) (1).png")),
                       Data("the new one".utf8))
    }

    func testNoTemporaryFileIsLeftBehind() throws {
        let folder = scratchDirectory("shots-names-tmp")
        _ = FileShotWriter().write(Data("x".utf8), into: folder, base: base, pathExtension: "png")
        _ = FileShotWriter().write(Data("y".utf8), into: folder, base: base, pathExtension: "png")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names.sorted(), ["\(base) (1).png", "\(base).png"])
    }

    func testAFolderThatIsNotThereIsRefusedAndNothingIsCreated() throws {
        let folder = scratchDirectory("shots-names-missing").appendingPathComponent("gone", isDirectory: true)
        XCTAssertEqual(FileShotWriter().write(Data("x".utf8), into: folder, base: base, pathExtension: "png"), .refused(.noFolder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testAFileWhereTheFolderShouldBeIsRefused() throws {
        let file = try write("not-a-folder", in: scratchDirectory("shots-names-file"))
        XCTAssertEqual(FileShotWriter().write(Data("x".utf8), into: file, base: base, pathExtension: "png"), .refused(.notAFolder))
    }

    func testAFolderNobodyMayWriteIsRefusedAsPermission() throws {
        let folder = scratchDirectory("shots-names-locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertEqual(FileShotWriter().write(Data("x".utf8), into: folder, base: base, pathExtension: "png"), .refused(.noPermission))
    }

    /// The fake walks the same ladder, so the session's tests rest on the same rule.
    func testTheFakeAndTheRealWriterCountTheSameWay() {
        XCTAssertEqual(ShotNames.candidate(base: base, pathExtension: "png", attempt: 0), "\(base).png")
        XCTAssertEqual(ShotNames.candidate(base: base, pathExtension: "png", attempt: 12), "\(base) (12).png")
        let writer = FakeWriter()
        writer.taken = ["\(base).png"]
        XCTAssertEqual(writer.write(Data(), into: URL(fileURLWithPath: "/x"), base: base, pathExtension: "png").url,
                       URL(fileURLWithPath: "/x/\(base) (1).png"))
    }
}
