import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// Tab 3 from the page's side: what the model is told, and what pressing
/// something does to it.
@MainActor
final class KeysTabTests: XCTestCase {

    private struct Wire {
        let hosted: HostsUIWire
        let model: HostsViewModel
    }

    /// A model whose first load is over. **Hold and await whatever moves before
    /// counting what it moves** — the model fires its own load from `init`, and
    /// a test that read `keys` straight away would be racing it.
    private func loaded(keys: WireKeys = WireKeys(),
                        agent: WireAgent = WireAgent()) async -> Wire {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined,
                                      keys: keys, agent: agent)
        let model = HostsViewModel(vm: hosted.vm)
        addTeardownBlock { await MainActor.run { model.stop() } }
        await model.firstLoad?.value
        await waitUntil("the first snapshot arrived") { !model.keys.isEmpty }
        return Wire(hosted: hosted, model: model)
    }

    func testTheModelIsToldAboutTheKeysAndTheDirectory() async {
        let w = await loaded()
        XCTAssertTrue(w.model.keysReadable)
        XCTAssertEqual(w.model.keys.map(\.name), ["id_ed25519"], "known_hosts is not a key")
        XCTAssertEqual(w.model.keys.first?.described?.fingerprint, "SHA256:abc123")
        XCTAssertEqual(w.model.directoryPermission, .ok)
        XCTAssertEqual(w.model.agent, .empty)
    }

    /// Press Fix, and the row the page draws changes — the verdict is the
    /// engine's next reading, not a guess made on this side about what the
    /// `chmod` did.
    func testFixingPermissionsChangesTheRowThePageDraws() async {
        let w = await loaded(keys: WireKeys(mode: 0o644))
        XCTAssertEqual(w.model.keys.first?.permission, .tooOpen(fix: 0o600),
                       "precondition: the row is in the state the button is for")

        await w.model.fixPermissions(of: "id_ed25519")
        await waitUntil("the new reading arrived") { w.model.keys.first?.permission == .ok }
        XCTAssertEqual(w.model.keyOutcome, .done)
        XCTAssertNil(w.model.busyKey, "the row was left disabled after the act")
    }

    /// The direction is read off the row, so one control does both and its word
    /// is always the word for what pressing it does.
    func testTheAgentControlLoadsThenUnloadsTheSameKey() async {
        let w = await loaded()
        let key = try? XCTUnwrap(w.model.keys.first)
        guard let key else { return }
        XCTAssertFalse(key.inAgent, "precondition: the agent is running and holding nothing")

        await w.model.setInAgent(key)
        await waitUntil("the badge came on") { w.model.keys.first?.inAgent == true }

        guard let held = w.model.keys.first else { return XCTFail("the row went away") }
        await w.model.setInAgent(held)
        await waitUntil("the badge went off") { w.model.keys.first?.inAgent == false }
    }

    /// **A folder nobody could read is not a folder with no keys**, and the page
    /// draws a different thing for each — so the two fields have to arrive
    /// separately rather than one being inferred from the other.
    func testAnUnreadableFolderIsNotAnEmptyOne() async {
        let hosted = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined,
                                      keys: WireKeys(names: nil))
        let model = HostsViewModel(vm: hosted.vm)
        addTeardownBlock { await MainActor.run { model.stop() } }
        await model.firstLoad?.value
        await waitUntil("the snapshot arrived") { !model.keysReadable }
        XCTAssertTrue(model.keys.isEmpty)
        XCTAssertEqual(model.directoryPermission, .unknown,
                       "a folder nobody could read has no verdict, and «ok» is a verdict")
    }

    /// The generator's refusals reach the sheet as sentences rather than as
    /// silence — and the one that matters is the name already taken, because it
    /// is the one a person meets by accident.
    func testAGenerationRefusedForItsNameSaysSo() async {
        let w = await loaded()
        await w.model.generate(type: .ed25519, name: "id_ed25519",
                               comment: "me@mac", passphrase: "")
        XCTAssertEqual(w.model.generated, .nameTaken)
        XCTAssertNotNil(HostsStr.sentence(for: .nameTaken))
        XCTAssertFalse(w.model.makingKey, "the sheet was left saying it was still working")
    }
}
