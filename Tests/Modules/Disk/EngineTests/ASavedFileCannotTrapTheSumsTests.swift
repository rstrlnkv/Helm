import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// **The figures in the saved scan are bounded one at a time, and the sums over
/// them saturate.**
///
/// `DiskEntry` and `DiskAdvice.Target` clamp what they decode to
/// `DiskEntry.byteCeiling`; one ceiling is not enough, because 8192 figures at
/// the ceiling pass an integer's top (`Int.max / byteCeiling + 1` of them do; 8191
/// do not). The sums the file can reach — the advice's total in the decoder
/// (`DiskAdvice.init(name:path:kind:modified:targets:)`), `DiskTreePrune` after a
/// removal, and the removal question's total — go through
/// `Sequence.saturatingSum()`. The file is one any process running as the user can
/// write, and `restoreLastScan` reads it on every opening of the page.
///
/// A trap takes the whole test process with it (`exited with unexpected signal
/// code 5`), so a regression in the two cases that used to trap reads as a crashed
/// bundle rather than as one red case.
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

    /// Two targets whose figures add past `Int.max`: the decoder's own sum once
    /// trapped, on the detached read `restoreLastScan` makes at every opening of the
    /// page. Unreachable by the bound alone only at two targets, so the case below
    /// is the one that needs the saturation.
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

    /// Two rows that each weigh nearly an integer, both in the basket: the question
    /// the dialog asks sums them.
    func testTheRemovalQuestionOverTwoHugeRowsSaturates() {
        let heavy = DiskAdvice(name: "a", path: "/v/a", bytes: Int.max - 1, kind: .cache)
        let other = DiskAdvice(name: "b", path: "/v/b", bytes: Int.max - 1, kind: .cache)
        let basket = [heavy, other].map {
            DiskEntry(name: $0.name, path: $0.path, bytes: 1, isDirectory: true,
                      noAccess: false, children: [])
        }
        let question = DiskRemovalPlan.question(basket: basket, advice: [heavy, other])
        XCTAssertEqual(question.paths.count, 2, "precondition: both rows are asked about")
        XCTAssertEqual(question.bytes, Int.max)
    }
}
