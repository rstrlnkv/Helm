import Foundation
import HelmContract
import XCTest
@testable import Module_Disk_Engine

/// What the engine's handler answers, arm by arm.
///
/// `RemovalWireFormatTests` beside this one holds the *types* that cross the
/// transport. Nothing held the handler itself, and the handler is the part the
/// codec helpers rewrite — every arm of it. Three shapes here, which is every
/// shape the nine engines have between them: an arm that answers a value, an arm
/// that refuses a payload it cannot read, and a name the engine does not know.
///
/// Read as replies, not as sizes: an empty reply is the refusal, and a
/// non-empty one has to decode as the type the caller asks for.
final class DiskHandlerReplyTests: XCTestCase {

    /// Held for the length of the test, and not incidentally: the handler
    /// captures the engine weakly, so `DiskEngine().transport.send(…)` on one
    /// line answers *empty* — the engine is gone by the time the reply is built,
    /// and every arm becomes a refusal. A test written that way passes whatever
    /// the arms do.
    private var engine: DiskEngine!

    override func setUp() {
        super.setUp()
        engine = DiskEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    private func reply(_ name: String, payload: Data = Data()) async throws -> Data {
        try await engine.transport.send(EngineCommand(name: name, payload: payload))
    }

    private func reply(_ command: DiskCommand, payload: Data = Data()) async throws -> Data {
        try await reply(command.rawValue, payload: payload)
    }

    func testAnArmThatAnswersAValueAnswersJSONOfThatValue() async throws {
        let data = try await reply(.volumes)

        let volumes = try JSONDecoder().decode([VolumeInfo].self, from: data)
        XCTAssertFalse(volumes.isEmpty, "the boot volume is always mounted")
    }

    /// The payload is not a `ScanRequest`, so no walk starts and the reply is
    /// empty — which the caller reads as "the module could not answer".
    func testAPayloadTheArmCannotReadIsRefusedWithAnEmptyReply() async throws {
        let data = try await reply(.scan, payload: Data("not a scan request".utf8))

        XCTAssertTrue(data.isEmpty, "a payload that cannot be read must not start a scan")
    }

    func testAnArmThatAnswersNothingAnswersAnEmptyReply() async throws {
        let data = try await reply(.cancel)

        XCTAssertTrue(data.isEmpty)
    }

    /// Refused at the door by `DiskCommand(rawValue:)`, before any arm.
    func testANameTheEngineDoesNotKnowIsRefusedWithAnEmptyReply() async throws {
        let data = try await reply("polish", payload: Data("{}".utf8))

        XCTAssertTrue(data.isEmpty)
    }
}
