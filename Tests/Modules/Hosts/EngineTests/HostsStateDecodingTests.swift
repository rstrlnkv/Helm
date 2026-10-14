import XCTest
@testable import Module_Hosts_Engine

/// What `HostsState.init(from:)` takes from the wire, written as JSON.
///
/// A stored default does **not** make an older payload decode: Swift's
/// synthesised `Decodable` wants the key regardless, and `JSONDecoder` abandons
/// the whole document rather than filling in the one field — every screen then
/// holds stale defaults. `KeepAwakeEngine.StatePayload` carried three comments
/// claiming otherwise and none of them was true, which is why this is a test
/// and not a sentence.
///
/// **Two fields are required and the rest are not.** The text of `~/.ssh/config`
/// and whether it could be read are required, so a payload without them is
/// taken for a truncated one and refused: `{}` must not draw an empty, writable
/// config as if it were the Mac's. Every other field is read when present and
/// defaulted when not; the keys' defaults are the cautious ones — no keys and
/// an unreachable agent say nothing about the Mac, where `keysReadable: true`
/// over an empty list would say it has none.
///
/// **Only JSON is built here**, never the value through its initialiser, so the
/// rows read the decoder and not a memberwise convenience. A refused payload is
/// asked *which* key it lacked: any throw would pass for a payload that fails
/// on a key this state no longer carries.
///
/// A payload that still has `hostsText`, `hostsReadable` and `backups` beside
/// the SSH fields is an older build's, and decodes: a key the state does not
/// know is ignored, not an error.
final class HostsStateDecodingTests: XCTestCase {

    /// The key a decode stopped at for want of it, or what else it threw.
    private func missingKey(in json: String) -> String? {
        do {
            _ = try JSONDecoder().decode(HostsState.self, from: Data(json.utf8))
            return nil
        } catch DecodingError.keyNotFound(let key, _) {
            return key.stringValue
        } catch {
            return "threw \(error)"
        }
    }

    private func decoded(_ json: String) throws -> HostsState {
        try JSONDecoder().decode(HostsState.self, from: Data(json.utf8))
    }

    /// The hosts-file keys of the build that had them, as an older payload
    /// carries them.
    private let hostsKeys = #""hostsText":"127.0.0.1\tlocalhost\n","hostsReadable":true,"backups":["2026-08-18T120000Z.hosts"]"#

    // MARK: - The two required fields

    func testAPayloadOfTheTwoRequiredFieldsDecodesWithTheCautiousDefaults() throws {
        let state = try decoded(#"{"sshText":"Host a\n  HostName b\n","sshReadable":false}"#)
        XCTAssertEqual(state.sshText, "Host a\n  HostName b\n")
        XCTAssertFalse(state.sshReadable)
        XCTAssertTrue(state.sshWritable)
        XCTAssertEqual(state.keys, [])
        XCTAssertFalse(state.keysReadable)
        XCTAssertEqual(state.directoryPermission, .unknown)
        XCTAssertEqual(state.agent, .unreachable)
        XCTAssertEqual(state.knownHostsText, "")
        XCTAssertFalse(state.knownHostsReadable)
        XCTAssertFalse(state.knownHostsWritable)
        XCTAssertEqual(state.home, "")
    }

    /// Without the config's text the payload is refused rather than read as an
    /// empty config, with the keys of the build before beside it or without them.
    func testAPayloadWithoutTheConfigTextIsRefused() {
        XCTAssertEqual(missingKey(in: #"{"sshReadable":true}"#), "sshText")
        XCTAssertEqual(missingKey(in: "{" + hostsKeys + #","sshReadable":true}"#), "sshText")
    }

    func testAPayloadWithoutTheReadableFlagIsRefused() {
        XCTAssertEqual(missingKey(in: #"{"sshText":""}"#), "sshReadable")
        XCTAssertEqual(missingKey(in: "{" + hostsKeys + #","sshText":""}"#), "sshReadable")
    }

    /// Which of the two it stops at is the decoder's order, so either is the
    /// right answer; a key of the old build is not.
    func testAnEmptyObjectIsRefused() {
        let stoppedAt = missingKey(in: "{}")
        XCTAssertTrue(["sshText", "sshReadable"].contains(stoppedAt ?? ""),
                      "`{}` stopped at \(stoppedAt ?? "nothing: it decoded")")
    }

    // MARK: - Payloads of the build before

    func testAPayloadThatStillCarriesTheHostsKeysDecodesAndReadsItsSSHFields() throws {
        let older = "{" + hostsKeys
            + #","sshText":"Host a\n","sshReadable":true,"sshWritable":false,"home":"/Users/x"}"#
        let state = try decoded(older)
        XCTAssertEqual(state.sshText, "Host a\n")
        XCTAssertTrue(state.sshReadable)
        XCTAssertFalse(state.sshWritable)
        XCTAssertEqual(state.home, "/Users/x")
    }

    // MARK: - The whole of it

    /// Every field present and none at its default, so a field the encoder or
    /// the decoder drops comes back different. The hosts keys are in the
    /// payload so that it decodes under a decoder that requires them and under
    /// one that ignores them.
    func testAWholePayloadSurvivesTheRoundTrip() throws {
        let wire = """
            {\(hostsKeys),
             "sshText":"Host a\\n  HostName b\\n","sshReadable":false,"sshWritable":false,
             "keys":[{"name":"id_ed25519","hasPublicHalf":true,"permission":{"ok":{}},"inAgent":true}],
             "keysReadable":true,
             "directoryPermission":{"tooOpen":{"fix":448}},
             "agent":{"holding":{"_0":["SHA256:abc"]}},
             "knownHostsText":"a ssh-ed25519 AAAA\\n","knownHostsReadable":true,"knownHostsWritable":true,
             "home":"/Users/x"}
            """
        let state = try decoded(wire)
        let minimal = try decoded("{" + hostsKeys + #","sshText":"","sshReadable":true}"#)
        XCTAssertNotEqual(state, minimal, "the payload is no different from the defaults, so a round trip proves nothing")
        XCTAssertEqual(state.keys.map(\.name), ["id_ed25519"])
        XCTAssertEqual(state.agent, .holding(["SHA256:abc"]))
        XCTAssertEqual(state.directoryPermission, .tooOpen(fix: 448))

        let back = try JSONDecoder().decode(HostsState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back, state)
    }
}
