import Foundation
import XCTest
@testable import Module_Disk_Engine

/// **An advice figure from a saved file is held to `0...DiskEntry.byteCeiling` in
/// the older form as in the current one.**
///
/// A row written before `targets` existed has only `bytes`; it decodes as one
/// target built through `Target(path:bytes:)`. That figure reaches the deletion
/// total (`DiskRemovalPlan.question`), so `Int.max` must not pass the ceiling and a
/// negative figure must not understate the sum. Both directions are tested: the
/// top and the bottom are different failures. The documents are JSON that omits
/// the key, never a re-encoded value of today's type.
final class AnOlderAdviceRowIsHeldToTheCeilingTests: XCTestCase {

    private func older(_ bytes: String) -> Data {
        Data(#"{"name":"c","path":"/v/c","bytes":\#(bytes),"kind":"cache"}"#.utf8)
    }

    private func newer(_ bytes: String) -> Data {
        Data(#"{"name":"c","path":"/v/c","bytes":0,"kind":"cache","targets":[{"path":"/v/c/x","bytes":\#(bytes)}]}"#.utf8)
    }

    private func decode(_ data: Data) throws -> DiskAdvice {
        try JSONDecoder().decode(DiskAdvice.self, from: data)
    }

    func testAnOlderRowAtIntMaxIsHeldToTheCeiling() throws {
        let row = try decode(older("9223372036854775807"))
        XCTAssertEqual(row.targets.count, 1, "precondition: the older form decodes as one target")
        XCTAssertEqual(row.targets[0].bytes, DiskEntry.byteCeiling)
        XCTAssertEqual(row.bytes, DiskEntry.byteCeiling)
    }

    func testAnOlderRowWithANegativeFigureWeighsNothing() throws {
        let row = try decode(older("-5000"))
        XCTAssertEqual(row.targets.count, 1, "precondition: the older form decodes as one target")
        XCTAssertEqual(row.targets[0].bytes, 0)
        XCTAssertEqual(row.bytes, 0)
    }

    func testACurrentRowIsHeldAtBothEnds() throws {
        XCTAssertEqual(try decode(newer("9223372036854775807")).bytes, DiskEntry.byteCeiling)
        XCTAssertEqual(try decode(newer("-5000")).bytes, 0)
    }

    /// The total the dialog shows: a negative older row beside an honest one must
    /// not subtract from it, and an `Int.max` one must not swamp it past the sum.
    func testTheDeletionTotalOverOlderRowsIsHonest() throws {
        let honest = DiskAdvice(name: "h", path: "/v/h", bytes: 1_000, kind: .cache)
        let negative = try decode(older("-5000"))
        let huge = try decode(older("9223372036854775807"))
        // `negative` and `huge` share the path /v/c; give them distinct ones.
        let rows = [honest,
                    DiskAdvice(name: "n", path: "/v/n", kind: .cache, targets: negative.targets),
                    DiskAdvice(name: "g", path: "/v/g", kind: .cache, targets: huge.targets)]
        let entries = rows.map {
            DiskEntry(name: $0.name, path: $0.path, bytes: 1, isDirectory: true,
                      noAccess: false, children: [])
        }
        let question = DiskRemovalPlan.question(basket: entries, advice: rows)
        XCTAssertEqual(question.bytes, 1_000 + DiskEntry.byteCeiling)
    }
}
