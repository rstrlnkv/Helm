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
    ///
    /// **Every port is named**, including here where the engine is asked to do
    /// nothing. It is not a formality: a default argument naming a real port
    /// turns a forgetful construction into an integration test, and the
    /// forgetful construction is always the one nobody meant.
    func testAnUnknownCommandIsAnsweredEmpty() async throws {
        let engine = HostsEngine(sshConfig: FakeSSHConfig(url: URL(fileURLWithPath: "/nowhere/.ssh/config"), text: "Host a\n"),
                                 knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(), agent: FakeSSHAgent(),
                                 generator: FakeGenerator(),
                                 // The home the gate judges against. Defaulted it
                                 // is this Mac's own, so a construction that
                                 // leaves it out asks the gate about the owner's
                                 // `~/.ssh` while claiming to be about nowhere.
                                 home: URL(fileURLWithPath: "/nowhere"),
                                 transport: LocalTransport())
        let reply = try await engine.transport.send(EngineCommand(name: "no-such-command"))
        XCTAssertEqual(reply, Data())
    }
}
