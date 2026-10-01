import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **At the narrowest pane, in every language, the host table's cards stand
/// on the SSH tab's margin on both sides, and nothing is drawn past them.**
///
/// The table moved from the page's 20 pt column to the tab's own margin
/// (`HostsSettingsPage.textBoxMargin`), so the text box and the cards share an
/// edge. `TheSSHTabStandsOnOneEdgeTests` reads that edge at 900 pt in the
/// process's language; `HostsRowsFitTheMinimumPaneTests` reads the host row at
/// 490 pt, in one language, and only bounds its right side — a table put back
/// on the 20 pt column draws to 470 against a bound of 479 and stays green.
/// This reads both sides, at 490 pt, in all eight languages, over a fixture
/// that draws every localised word the table has: the trusted and missing
/// badges, the Forget buttons, the heading over the other trusts, the revoked
/// badge and the sentence for a hashed line.
///
/// Geometry only, so one named appearance.
@MainActor
final class TheSSHHostTableKeepsTheTabEdgeAtTheNarrowestPaneTests: XCTestCase {

    /// The pane at the settings window's minimum, as
    /// `HostsRowsFitTheMinimumPaneTests` takes it.
    private let pane: CGFloat = 490
    private var renders: [MountedRender] = []
    private var models: [HostsViewModel] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        models.forEach { $0.stop() }
        renders = []
        models = []
        super.tearDown()
    }

    private static let key = "AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"

    /// Two hosts — one on a key that exists, one on a key that is gone and
    /// already trusted — and two trusts belonging to neither: a revoked one and
    /// a hashed one.
    private func state() -> HostsState {
        let config = """
            Host build-runner-eu-west-1
                HostName build-runner-eu-west-1.internal.corp.example.com
                User deploy
                IdentityFile ~/.ssh/id_ed25519_work_laptop

            Host a
                HostName a.example
                IdentityFile ~/.ssh/id_gone_missing_key_with_a_long_name

            """
        let known = "a.example ssh-ed25519 \(Self.key) me@mac\n"
            + "@revoked old.example ssh-ed25519 \(Self.key) x\n"
            + "|1|c2FsdHNhbHRzYWx0c2FsdHNhbHQ=|aGFzaGhhc2hoYXNoaGFzaGhhc2g= ssh-ed25519 \(Self.key)\n"
        return HostsState(
            hostsText: "127.0.0.1\tlocalhost\n", sshText: config,
            keys: [KeyRow(name: "id_ed25519_work_laptop", hasPublicHalf: true,
                          described: KeyInventory.described(
                            "256 SHA256:5Xb9pQ2mK7vN8zR1tY4wA6cE0jH3sL5uD7fG9iO2kM8 me@mac (ED25519)"),
                          modified: Date(timeIntervalSince1970: 1_700_000_000),
                          permission: .ok,
                          publicText: "ssh-ed25519 AAAA me@mac\n", inAgent: false)],
            keysReadable: true, directoryPermission: .ok, agent: .empty,
            knownHostsText: known, home: "/Users/someone")
    }

    /// Every layer's frame in the host's coordinates.
    private func layers(_ host: NSView) -> [CGRect] {
        guard let root = host.layer else { return [] }
        var out: [CGRect] = []
        func walk(_ layer: CALayer) {
            out.append(root.convert(layer.bounds, from: layer))
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return out
    }

    /// The cards: the rounded layers that span the table, found by their
    /// corners and not by where they stand, so a card on the wrong edge is
    /// still found and judged.
    private func cards(_ host: NSView) -> [CGRect] {
        guard let root = host.layer else { return [] }
        var out: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.width > pane / 2, layer.bounds.height > 60 {
                out.append(root.convert(layer.bounds, from: layer))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return out
    }

    func testTheCardsStandOnTheTabMarginOnBothSidesInEveryLanguage() {
        let margin = HostsSettingsPage.textBoxMargin
        var forgets: [String] = []
        AppLanguage.each { language in
            let model = HostsViewModel(vm: ModuleViewModel(transport: LocalTransport()))
            models.append(model)
            model.adopt(state())
            XCTAssertEqual(model.hostRows.count, 2, "\(language): precondition — the fixture's two hosts")
            XCTAssertEqual(model.otherTrusted.count, 2, "\(language): precondition — the two other trusts")
            forgets.append(HostsStr.forgetHost)

            let render = MountedRender(SSHHostsTable(hvm: model, select: { _ in }),
                                       width: pane, height: 1000, appearance: .aqua)
            renders.append(render)
            render.settle(30)

            let drawn = cards(render.host)
            XCTAssertEqual(drawn.count, 3, "\(language): two host cards and the other-trusts card, found \(drawn)")
            for card in drawn {
                XCTAssertEqual(card.minX, margin, accuracy: 0.5,
                               "\(language): a card starts at \(card.minX), not on the tab's \(margin) pt margin")
                XCTAssertEqual(card.maxX, pane - margin, accuracy: 0.5,
                               "\(language): a card ends at \(card.maxX), not on the tab's margin at \(pane - margin)")
            }

            // Everything that is not a full-width container stays between the
            // two margins — a badge or a button that does not fit shows here.
            let content = layers(render.host).filter { $0.width > 0 && $0.width < pane - 1 }
            XCTAssertGreaterThan(content.count, 20, "\(language): nothing rendered")
            let left = content.map(\.minX).min() ?? -1
            let right = content.map(\.maxX).max() ?? .infinity
            XCTAssertGreaterThanOrEqual(left, margin - 0.5, "\(language): something is drawn at x = \(left), left of the margin")
            XCTAssertLessThanOrEqual(right, pane - margin + 0.5, "\(language): something is drawn to x = \(right), past the margin")

            // Inside the cards the rows start one card padding in, and do not
            // walk in from it: a row too wide for the pane is centred by
            // SwiftUI, not drawn past the edge.
            let inner = content.filter { $0.minX > margin + 1 }
            XCTAssertEqual(inner.map(\.minX).min() ?? -1, margin + HelmSpace.s5, accuracy: 1,
                           "\(language): the rows start at \(inner.map(\.minX).min() ?? -1)")

            // The addresses and fingerprints: one line each.
            let lines = render.host.everyView(named: "AppKitTextInteractionView")
                .map { $0.convert($0.bounds, to: render.host) }
            XCTAssertGreaterThanOrEqual(lines.count, 5, "\(language): two addresses and three fingerprints, found \(lines.count)")
            for line in lines {
                XCTAssertLessThanOrEqual(line.height, 20, "\(language): a detail line is \(line.height) pt tall — it wrapped")
            }
        }
        XCTAssertEqual(Set(forgets).count, AppLanguage.allCases.count,
                       "precondition — the loop did not draw eight languages: \(forgets)")
    }
}
