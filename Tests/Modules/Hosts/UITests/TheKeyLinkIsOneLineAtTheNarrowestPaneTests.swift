import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The key link on a host row is one line at the narrowest pane, in every
/// language.** A `.link` button given its text as a title ignored the line limit
/// outside it and wrapped in German, growing the card 142 -> 158; the label has
/// to carry its own limit. The «Check agent» link of the Keys tab is measured
/// the same way: one height of its line across the eight languages.
@MainActor
final class TheKeyLinkIsOneLineAtTheNarrowestPaneTests: XCTestCase {

    private var keep: [AnyObject] = []
    override func tearDown() async throws {
        await MainActor.run {
            keep.compactMap { $0 as? MountedRender }.forEach { $0.drop() }
            keep.compactMap { $0 as? HostsViewModel }.forEach { $0.stop() }
            keep = []
        }
    }

    private static func state(key: String) -> HostsState {
        HostsState(
            hostsText: "127.0.0.1\tlocalhost\n",
            sshText: "Host build-runner-eu-west-1\n    HostName build-runner-eu-west-1.internal.corp.example.com\n    User deploy\n    IdentityFile ~/.ssh/\(key)\n",
            keys: [KeyRow(name: key, hasPublicHalf: true,
                          described: KeyInventory.described("256 SHA256:5Xb9pQ2mK7vN8zR1tY4wA6cE0jH3sL5uD7fG9iO2kM8 me@mac (ED25519)"),
                          modified: Date(timeIntervalSince1970: 1_700_000_000), permission: .ok,
                          publicText: "ssh-ed25519 AAAA me@mac\n", inAgent: false)],
            keysReadable: true, directoryPermission: .ok, agent: .empty,
            knownHostsText: "", home: "/Users/someone")
    }

    private func heights(of view: (HostsViewModel) -> AnyView, key: String, minimum: CGSize) -> [String: CGFloat] {
        var out: [String: CGFloat] = [:]
        AppLanguage.each { language in
            let model = HostsViewModel(vm: ModuleViewModel(transport: LocalTransport()))
            keep.append(model)
            model.adopt(Self.state(key: key))
            let render = MountedRender(view(model), width: minimum.width, height: minimum.height, appearance: .aqua)
            keep.append(render)
            render.settle(30)
            guard let root = render.host.layer else { return }
            var cards: [CGRect] = []
            func walk(_ l: CALayer) {
                if l.cornerRadius > 0.01, l.bounds.width > 245, l.bounds.height > 60 { cards.append(root.convert(l.bounds, from: l)) }
                l.sublayers?.forEach(walk)
            }
            walk(root)
            out[language.rawValue] = cards.first?.height ?? -1
        }
        return out
    }

    func testTheKeyLinkIsOneLineInEveryLanguage() {
        for key in ["id_ed25519_work_laptop", "id_ed25519_a_key_with_a_much_longer_name_than_anyone_would_choose"] {
            let h = heights(of: { AnyView(SSHHostsTable(hvm: $0, select: { _ in })) }, key: key, minimum: CGSize(width: 490, height: 600))
            XCTAssertGreaterThan(h.count, 7, "precondition — the loop did not reach every language")
            XCTAssertFalse(h.values.contains(-1), "precondition — no card was found: \(h)")
            XCTAssertEqual(Set(h.values).count, 1, "the host card is not one height across languages — the key link wrapped (\(key)): \(h.sorted { $0.key < $1.key })")
        }
    }

    /// With no keys the table is its agent line and nothing else, so the table's
    /// own height is that line's: the same in every language, unless the sentence
    /// or the link beside it wrapped.
    func testTheAgentLineStaysOneLineAtTheNarrowestPane() {
        var lines: [String: CGFloat] = [:]
        AppLanguage.each { language in
            let model = HostsViewModel(vm: ModuleViewModel(transport: LocalTransport()))
            keep.append(model)
            var state = Self.state(key: "id_ed25519_work_laptop")
            state.keys = []
            state.agent = .unreachable
            model.adopt(state)
            let render = MountedRender(KeysTable(hvm: model), width: 490, height: 600, appearance: .aqua)
            keep.append(render)
            render.settle(30)
            lines[language.rawValue] = render.fittingHeight
        }
        XCTAssertGreaterThan(lines.count, 7, "precondition — the loop did not reach every language")
        XCTAssertFalse(lines.values.contains { $0 < 10 }, "precondition — nothing was drawn: \(lines)")
        XCTAssertEqual(Set(lines.values).count, 1, "the agent line wrapped in some language: \(lines.sorted { $0.key < $1.key })")
    }
}
