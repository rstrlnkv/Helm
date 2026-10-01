import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// **An advice row in the shape an older build saved — no `targets` key — is
/// held to the ceiling the newer shape is held to.**
///
/// `DiskAdvice.Target.init(from:)` clamps a target's figure to
/// `0...DiskEntry.byteCeiling`. A row saved before targets existed decodes its
/// one target from the row's own `bytes` through the memberwise initializer,
/// which clamps nothing: `Int.max` comes through as a row past the ceiling and a
/// negative figure as a negative row, which takes from the removal question's
/// total beside it. The file is one any process running as the user can write.
///
/// **A documented gap (Q-legacy-advice), skipped unless `HELM_KNOWN_GAPS=1`**, with
/// the reproduction below the skip untouched.
final class AnOlderAdviceRowIsHeldToTheCeilingTests: XCTestCase {

    private static var knownGapsRun: Bool { ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1" }

    private func row(bytes: String) throws -> DiskAdvice {
        let json = #"{"name":"old","path":"/v/old","bytes":\#(bytes),"kind":"largeOld"}"#
        return try JSONDecoder().decode(DiskAdvice.self, from: Data(json.utf8))
    }

    func testAnOlderRowAtTheTopOfAnIntegerIsHeldToTheCeiling() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap Q-legacy-advice: a row with no targets key is not clamped")
        let decoded = try row(bytes: "9223372036854775807")
        XCTAssertEqual(decoded.targets.count, 1, "precondition: the older shape decodes as one target")
        XCTAssertLessThanOrEqual(decoded.targets[0].bytes, DiskEntry.byteCeiling, "the target's figure")
        XCTAssertLessThanOrEqual(decoded.bytes, DiskEntry.byteCeiling, "the row's figure")
    }

    func testAnOlderRowWithANegativeFigureIsHeldAtZero() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap Q-legacy-advice: a row with no targets key is not clamped")
        let decoded = try row(bytes: "-1000000000000")
        XCTAssertEqual(decoded.targets.count, 1, "precondition: the older shape decodes as one target")
        XCTAssertGreaterThanOrEqual(decoded.bytes, 0, "a negative row")
        // What the negative row does to the question beside a real folder.
        let folder = DiskEntry(name: "f", path: "/v/f", bytes: 5_000_000_000, isDirectory: true,
                               noAccess: false, children: [])
        let basket = [DiskEntry(name: "old", path: "/v/old", bytes: decoded.bytes, isDirectory: false,
                                noAccess: false, children: []), folder]
        let question = DiskRemovalPlan.question(basket: basket, advice: [decoded])
        XCTAssertGreaterThanOrEqual(question.bytes, folder.bytes,
                                    "the question about two rows weighs less than one of them")
    }
}
