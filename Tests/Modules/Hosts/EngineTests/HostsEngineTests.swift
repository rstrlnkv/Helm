import XCTest
import HelmContract
@testable import Module_Hosts_Engine

final class HostsEngineTests: XCTestCase {

    /// The id is data — it names the `module.hosts.*` keys on people's
    /// machines — so it is pinned here as well as in the host's own guard.
    func testTheModuleIDIsHosts() {
        XCTAssertEqual(HostsEngine.moduleID, "hosts")
    }

    /// A name the enum cannot parse is refused at the door rather than falling
    /// through a `default` nobody re-reads.
    func testAnUnknownCommandIsAnsweredEmpty() async throws {
        let engine = HostsEngine()
        let reply = try await engine.transport.send(EngineCommand(name: "no-such-command"))
        XCTAssertEqual(reply, Data())
    }
}
