import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// The figures in the saved scan are bounded one at a time, and the sums over
/// them saturate.
///
/// `DiskEntry` and `DiskAdvice.Target` clamp what they decode to
/// `DiskEntry.byteCeiling`, but `Int.max / byteCeiling + 1` figures at the
/// ceiling still pass an integer's top. So the sums the file reaches (the
/// advice's total in the decoder, `DiskTreePrune` after a removal, the removal
/// question's total) go through `Sequence.saturatingSum()`. Any process running
/// as the person can write the file, and `restoreLastScan` reads it at every
/// opening of the page.
///
/// A trap takes the whole test process with it, so a regression here reads as a
/// crashed bundle rather than one red case.
final class ASavedFileCannotTrapTheSumsTests: XCTestCase {

    private func entry(_ path: String, bytes: String, children: [String] = []) -> String {
        #"{"name":"\#((path as NSString).lastPathComponent)","path":"\#(path)","bytes":\#(bytes),"# +
            #""isDirectory":true,"noAccess":false,"children":[\#(children.joined(separator: ","))]}"#
    }

    private func advice(targets: [String]) -> String {
        let listed = targets.enumerated().map { #"{"path":"/v/c/\#($0.offset)","bytes":\#($0.element)}"# }
        return #"{"name":"c","path":"/v/c","bytes":0,"kind":"cache","targets":[\#(listed.joined(separator: ","))]}"#
    }

    private func saved(root: String, advice: [String] = []) -> String {
        #"{"savedAt":0,"result":{"root":\#(root),"freeBytes":0,"filesScanned":1,"seconds":1,"# +
            #""advice":[\#(advice.joined(separator: ","))]}}"#
    }

    /// Plants `json` where a store reads its saved scan, and reads it the way
    /// `restoreLastScan` does.
    private func load(_ json: String) throws -> ScanStore.Cached? {
        let store = ScanStore(directory: scratchDirectory("disk-planted-store"))
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.fileURL)
        return store.load()
    }

    /// A negative count and a duration of 1e300 are read as 0 and one day, the
    /// bound every other figure in the file already has.
    func testTheCountAndTheDurationDecodedFromAFileAreBounded() throws {
        let json = saved(root: entry("/v", bytes: "1"))
            .replacingOccurrences(of: #""filesScanned":1,"seconds":1"#,
                                  with: #""filesScanned":-5,"seconds":1e300"#)
        let result = try XCTUnwrap(try load(json), "precondition: the planted file did not decode").result
        XCTAssertEqual(result.filesScanned, 0, "a negative count is read as 0")
        XCTAssertEqual(result.seconds, 86_400, "a duration of 1e300 is read as one day")
    }

    /// One target at `Int.max` is held to the ceiling every other figure in the file
    /// is held to; unbounded, a basket holding two such rows sums past an integer.
    func testATargetFigureDecodedFromAFileIsBounded() throws {
        let cached = try XCTUnwrap(try load(saved(root: entry("/v", bytes: "1"),
                                                  advice: [advice(targets: ["9223372036854775807"])])),
                                   "precondition: the planted file did not decode at all")
        let row = try XCTUnwrap(cached.result.advice.first, "precondition: the advice decoded")
        XCTAssertLessThanOrEqual(row.targets[0].bytes, DiskEntry.byteCeiling,
                                 "a target's figure is read from the file with no bound")
        XCTAssertLessThanOrEqual(row.bytes, DiskEntry.byteCeiling,
                                 "an advice row weighs \(row.bytes) bytes, past the ceiling")
    }

    /// Two targets whose figures add past `Int.max`. The bound alone covers two
    /// targets; the case below is the one that needs the saturation.
    func testTwoTargetsOutweighingAnIntegerDoNotTrapTheRead() throws {
        let cached = try load(saved(root: entry("/v", bytes: "1"),
                                    advice: [advice(targets: ["9223372036854775807", "1"])]))
        XCTAssertNotNil(cached, "a planted file that cannot be read should be read as no file")
    }

    /// A folder with more children at the ceiling than an integer holds, then a
    /// removal of one of them: the prune sums every child of that folder.
    /// `8_193 × 2⁵⁰` is past `Int.max`, so a per-figure bound alone cannot be the
    /// answer to a sum.
    func testAPruneOverManyChildrenAtTheCeilingDoesNotTrap() throws {
        let count = Int.max / DiskEntry.byteCeiling + 2
        let children = (0..<count).map { entry("/v/f/\($0)", bytes: "9223372036854775807") }
        let cached = try XCTUnwrap(try load(saved(root: entry("/v", bytes: "1", children: [
            entry("/v/f", bytes: "9223372036854775807", children: children),
        ]))), "precondition: the planted file did not decode")
        let folder = try XCTUnwrap(cached.result.root.children.first)
        XCTAssertEqual(folder.children.count, count, "precondition: every child decoded")
        XCTAssertEqual(folder.children[0].bytes, DiskEntry.byteCeiling,
                       "precondition: each child is held to the ceiling")
        let pruned = DiskTreePrune.removing(paths: ["/v/f/0"], from: cached.result.root)
        XCTAssertEqual(pruned.children.first?.children.count, count - 1)
    }

    /// More targets at the ceiling than an integer holds: the bound on each figure
    /// does not bound the advice's total, which saturates instead of trapping.
    func testAdviceWhoseTargetsAtTheCeilingSumPastAnIntegerSaturates() throws {
        let count = Int.max / DiskEntry.byteCeiling + 2
        let cached = try XCTUnwrap(try load(saved(
            root: entry("/v", bytes: "1"),
            advice: [advice(targets: Array(repeating: "9223372036854775807", count: count))])),
                                   "precondition: the planted file did not decode")
        let row = try XCTUnwrap(cached.result.advice.first, "precondition: the advice decoded")
        XCTAssertEqual(row.targets.count, count, "precondition: every target decoded")
        XCTAssertEqual(row.targets[0].bytes, DiskEntry.byteCeiling,
                       "precondition: each target is held to the ceiling")
        XCTAssertEqual(row.bytes, Int.max, "the total is held at the top of an integer")
    }

    /// More rows at the ceiling than an integer holds, all in the basket: the
    /// question the dialog asks sums them. Each row is held to the ceiling by
    /// `Target`, so two rows cannot overflow it.
    func testTheRemovalQuestionOverManyHugeRowsSaturates() {
        let count = Int.max / DiskEntry.byteCeiling + 2
        let rows = (0..<count).map {
            DiskAdvice(name: "a\($0)", path: "/v/a\($0)", bytes: Int.max - 1, kind: .cache)
        }
        let basket = rows.map {
            DiskEntry(name: $0.name, path: $0.path, bytes: 1, isDirectory: true,
                      noAccess: false, children: [])
        }
        let question = DiskRemovalPlan.question(basket: basket, advice: rows)
        XCTAssertEqual(question.paths.count, count, "precondition: every row is asked about")
        XCTAssertEqual(question.bytes, Int.max)
    }
}
