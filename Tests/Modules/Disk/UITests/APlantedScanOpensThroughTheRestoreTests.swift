import Foundation
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// **A planted `last-scan.json`, opened the way the page opens it.**
///
/// `ASavedFileCannotTrapTheSumsTests` and `TheBasketTotalSaturatesTests` each
/// reach one sum from a value built in the test. This case reaches all four from
/// one file, through the road a person takes: the view model's own
/// `restoreLastScan` at construction, the advice rows put in the basket, the
/// removal question, and a removal answered by the engine so the tree is pruned.
///
/// Every figure in the file is `Int.max`; each is held to `DiskEntry.byteCeiling`
/// as it is decoded, and the file carries more of them than an integer holds
/// (`Int.max / byteCeiling + 2`) in two places — the children of one folder and
/// the targets of one cache row — so each sum below is past an integer:
///
/// - the cache row's total, in `DiskAdvice`'s decoder;
/// - the basket's total: the cache row, a large-file row and the folder;
/// - the removal question's total over the same three;
/// - `DiskTreePrune` over the folder's children before and after one is removed.
///
/// A sum that traps takes the test process with it, so a regression reads as a
/// crashed bundle rather than one red case.
@MainActor
final class APlantedScanOpensThroughTheRestoreTests: XCTestCase {

    private static let top = "9223372036854775807"

    private func entry(_ path: String, children: [String] = []) -> String {
        #"{"name":"\#((path as NSString).lastPathComponent)","path":"\#(path)","bytes":\#(Self.top),"# +
            #""isDirectory":true,"noAccess":false,"children":[\#(children.joined(separator: ","))]}"#
    }

    func testAPlantedScanPastAnIntegerOpensBasketsAndPrunesWithoutATrap() async throws {
        let mount = scratchDirectory("disk-planted-restore").path
        let store = ScanStore(directory: scratchDirectory("disk-planted-restore-store"))
        let count = Int.max / DiskEntry.byteCeiling + 2
        let folder = mount + "/big"
        let cache = mount + "/cache"
        let old = mount + "/old.dmg"
        let children = (0..<count).map { entry(folder + "/\($0)") }
        let targets = (0..<count).map { #"{"path":"\#(cache)/\#($0)","bytes":\#(Self.top)}"# }
        let advice = [
            #"{"name":"cache","path":"\#(cache)","bytes":0,"kind":"cache","# +
                #""targets":[\#(targets.joined(separator: ","))]}"#,
            #"{"name":"old.dmg","path":"\#(old)","bytes":\#(Self.top),"kind":"largeOld","# +
                #""targets":[{"path":"\#(old)","bytes":\#(Self.top)}]}"#,
        ]
        // `savedAt` as `JSONEncoder` writes a date: seconds since 2001. A minute
        // ago, so the restore's age guard admits it.
        let savedAt = Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate
        let json = #"{"savedAt":\#(savedAt),"result":{"root":\#(entry(mount, children: [entry(folder, children: children)])),"# +
            #""freeBytes":\#(Self.top),"filesScanned":1,"seconds":1,"advice":[\#(advice.joined(separator: ","))]}}"#
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.fileURL)

        let wire = AnsweringTransport(volumes: [])
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire), store: store)
        let start = Date()
        while !dvm.restored, Date().timeIntervalSince(start) < 10 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await settle()

        // The subject happened: the file was restored, whole, and drawn.
        XCTAssertTrue(dvm.restored, "precondition: the planted file was never restored")
        let result = try XCTUnwrap(dvm.result, "precondition: nothing on screen after the restore")
        XCTAssertEqual(result.root.children.first?.children.count, count, "precondition: every child decoded")
        XCTAssertEqual(result.root.children.first?.children.first?.bytes, DiskEntry.byteCeiling,
                       "precondition: each figure is held to the ceiling")
        XCTAssertFalse(dvm.segments.isEmpty, "the ring drew nothing for the restored tree")

        // The advice's own total, from the decoder.
        let cacheRow = try XCTUnwrap(result.advice.first { $0.path == cache }, "precondition: the cache row decoded")
        XCTAssertEqual(cacheRow.targets.count, count, "precondition: every target decoded")
        XCTAssertEqual(cacheRow.bytes, .max, "the cache row's total is held at the top of an integer")
        let oldRow = try XCTUnwrap(result.advice.first { $0.path == old })
        XCTAssertEqual(oldRow.bytes, DiskEntry.byteCeiling, "a target's figure is held to the ceiling")

        // The basket and the question, over the two rows and the folder.
        let big = try XCTUnwrap(result.root.children.first)
        dvm.basket = [dvm.entry(for: cacheRow), dvm.entry(for: oldRow), big]
        XCTAssertEqual(dvm.basket.count, 3, "precondition: three rows in the basket")
        XCTAssertEqual(dvm.basketBytes, .max, "the basket's total")
        let question = dvm.removalQuestion
        XCTAssertEqual(question.count, count + 2, "the question names every target the press sends")
        XCTAssertEqual(question.bytes, .max, "the question's total")

        // A removal answered by the engine: the tree is pruned in hand.
        wire.answerTrash(with: DiskRemoval(removed: [folder + "/0"], refused: [], freedBytes: 1))
        await dvm.emptyBasket()
        XCTAssertEqual(wire.trashRequests.count, 1, "precondition: the press reached the engine")
        XCTAssertEqual(dvm.result?.root.children.first?.children.count, count - 1,
                       "the removed child is still in the tree, so no prune ran")
    }
}
