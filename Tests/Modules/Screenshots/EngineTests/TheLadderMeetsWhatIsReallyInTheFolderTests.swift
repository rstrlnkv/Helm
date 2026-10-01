import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **What sits under a screenshot's name is not always a screenshot.** The
/// ladder past "(1)" meets whatever a folder holds: a folder of that name, a
/// symbolic link to somebody's file, a link to nothing at all — and two
/// captures landing in the same second, which is the seam called twice. None of
/// them is written through, none is replaced, and each is one more step up the
/// ladder. The real writer on a real folder, because what "exists" means for a
/// dangling link is the file system's answer and not a set of names.
final class TheLadderMeetsWhatIsReallyInTheFolderTests: XCTestCase {

    private let base = "Screenshot 2026-09-30 at 14.02.11"

    private func name(_ attempt: Int) -> String {
        ShotNames.candidate(base: base, pathExtension: "png", attempt: attempt)
    }

    func testAFolderALinkToAFileAndALinkToNothingAreEachStepsAndNoneIsWrittenThrough() throws {
        let folder = scratchDirectory("shots-ladder")
        let elsewhere = scratchDirectory("shots-ladder-elsewhere")
        let manager = FileManager.default

        try manager.createDirectory(at: folder.appendingPathComponent(name(0)), withIntermediateDirectories: false)
        let precious = elsewhere.appendingPathComponent("precious.txt")
        let bytes = Data("somebody's file, reached through a link".utf8)
        try bytes.write(to: precious)
        try manager.createSymbolicLink(atPath: folder.appendingPathComponent(name(1)).path,
                                       withDestinationPath: precious.path)
        let nowhere = elsewhere.appendingPathComponent("not-there-yet.png")
        try manager.createSymbolicLink(atPath: folder.appendingPathComponent(name(2)).path,
                                       withDestinationPath: nowhere.path)

        let result = FileShotWriter().write(Data("the new one".utf8), into: folder, base: base)

        XCTAssertEqual(result, .written(folder.appendingPathComponent(name(3))))
        XCTAssertEqual(try Data(contentsOf: precious), bytes, "a link's target was written through")
        XCTAssertFalse(manager.fileExists(atPath: nowhere.path), "a dangling link was followed and its target created")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(manager.fileExists(atPath: folder.appendingPathComponent(name(0)).path, isDirectory: &isDirectory)
                      && isDirectory.boolValue, "the folder under the plain name was replaced")
    }

    /// Every name up to "(999)" taken: refused by name, and the bytes that were
    /// staged for the attempt are not left behind as a hidden file.
    func testEveryNameTakenIsRefusedAndLeavesNothingBehind() throws {
        let folder = scratchDirectory("shots-ladder-full")
        for attempt in 0..<ShotNames.limit {
            XCTAssertTrue(FileManager.default.createFile(atPath: folder.appendingPathComponent(name(attempt)).path,
                                                         contents: Data()))
        }
        let result = FileShotWriter().write(Data("one too many".utf8), into: folder, base: base)
        XCTAssertEqual(result, .refused(.namesExhausted))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names.count, ShotNames.limit, "the folder gained or lost a file: \(names.count)")
        XCTAssertFalse(names.contains { $0.hasPrefix(".helm-shot-") }, "a staged file was left behind")
    }

    /// Two captures in the same second, written at once — the seam called
    /// twice before the first write finished. Each gets its own name, and each
    /// name holds the bytes of the capture that claimed it.
    func testCapturesInTheSameSecondWrittenAtOnceEachKeepTheirOwnBytes() throws {
        let folder = scratchDirectory("shots-ladder-race")
        let count = 16
        final class Outcomes: @unchecked Sendable {
            let lock = NSLock()
            var byIndex: [Int: ShotWrite] = [:]
        }
        let outcomes = Outcomes()
        let base = base
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let outcome = FileShotWriter().write(Data("capture \(index)".utf8), into: folder, base: base)
            outcomes.lock.withLock { outcomes.byIndex[index] = outcome }
        }
        let results = outcomes.byIndex
        var claimed: Set<String> = []
        for index in 0..<count {
            guard case .written(let url)? = results[index] else { return XCTFail("capture \(index): \(String(describing: results[index]))") }
            XCTAssertTrue(claimed.insert(url.lastPathComponent).inserted, "two captures were given \(url.lastPathComponent)")
            XCTAssertEqual(try Data(contentsOf: url), Data("capture \(index)".utf8),
                           "\(url.lastPathComponent) holds another capture's bytes")
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)),
                       Set((0..<count).map(name)), "the folder is not the first \(count) rungs of the ladder")
    }
}
