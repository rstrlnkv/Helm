// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **The state Helm declined to ask about, said on the screen.**
///
/// An automatic connect may not open the System keychain, and an empty credential
/// cache therefore means a rule cannot raise its tunnel at all. The engine knows
/// (`VPNSecretBook`); until this landed the only account of it was a line in
/// `~/Library/Logs/Helm/helm.log`, which is the outcome CLAUDE.md forbids — the app
/// silently not doing the thing it was asked.
///
/// Two surfaces, because they answer different questions: the banner over the
/// connections says which configuration is stuck, and the rule's own row is where
/// somebody looks when a rule stopped working. One sentence, from one place.
@MainActor
final class OnePressOfConnectIsAskedForTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    // MARK: - The sentence

    /// Parameterized by language rather than reading `AppLanguage.current`: the
    /// suite runs in this machine's language, so a test that asks `current` checks
    /// English eight times.
    func testTheSentenceIsWrittenInAllEightLanguages() {
        let english = VPNStr.secretNeedsAPress("Office", language: .en)
        XCTAssertFalse(english.isEmpty)
        for language in AppLanguage.allCases where language != .en {
            let it = VPNStr.secretNeedsAPress("Office", language: language)
            XCTAssertFalse(it.isEmpty, "\(language) says nothing")
            XCTAssertNotEqual(it, english,
                              "\(language) fell back to English, which is what a missing row in "
                              + "the table looks like")
        }
    }

    /// **It names a control, so it has to name the control this app draws.** A
    /// 0.9.0 changelog entry told people to press «Configure panel» and all seven
    /// translations faithfully translated a button that says «Edit panel». The word
    /// on the card comes from `VPNStr.cardWord`, and every language's own spelling
    /// of it has to appear in its own sentence.
    func testEachLanguageNamesTheButtonAsThatLanguageSpellsIt() {
        for language in AppLanguage.allCases {
            let word = VPNStr.cardWord(.connect, language: language)
            XCTAssertTrue(VPNStr.secretNeedsAPress("Office", language: language).contains(word),
                          "\(language): the sentence tells the person to press something the "
                          + "card does not call «\(word)»")
        }
    }

    /// And the configuration is quoted the way that language quotes a name — the
    /// marks are `Quoted`'s, not this table's, which is the fix four rows of this
    /// same file already needed.
    func testTheConfigurationIsQuotedTheWayEachLanguageQuotesOne() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(VPNStr.secretNeedsAPress("Office", language: language)
                            .contains(Quoted("Office", language: language)),
                          "\(language) spells its own quotation marks")
        }
    }

    // MARK: - The wire reaches the model

    func testTheModelPublishesWhatTheEngineCouldNotRead() {
        let transport = LocalTransport()
        let vm = VPNViewModel(transport: transport)
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "1", name: "Office", status: .disconnected,
                                        kind: "IPSec")],
            autoConnected: [], defaultName: "Office", lastAutomation: nil)
        payload.secretsBehindAPrompt = ["Office"]
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        pump { !vm.connections.isEmpty }

        XCTAssertEqual(vm.secretsBehindAPrompt, ["Office"],
                       "the engine published it and the page could not see it")
    }

    // MARK: - Both surfaces draw it

    /// The banner over the connections, measured the way the refusal banner beside
    /// it is: a **wider fill** appears above the first section card. The control is
    /// the same page with nothing locked, so «something was drawn» is the reading
    /// rather than an alignment that would hold on a page drawing no banner at all.
    ///
    /// The rule on this page points somewhere else, which is what makes the banner
    /// the surface — see the pair below.
    func testTheBannerOverTheConnectionsAppearsAndSharesTheCardsColumn() {
        let quiet = widestFillAboveTheFirstCard(locked: [], ruleFor: "Other")
        let stuck = widestFillAboveTheFirstCard(locked: ["One"], ruleFor: "Other")
        guard let quietFill = quiet.fill, let banner = stuck.fill else {
            return XCTFail("nothing filled was drawn above the first card at all: "
                           + "\(String(describing: quiet.fill)) / "
                           + "\(String(describing: stuck.fill))")
        }
        XCTAssertGreaterThan(banner.count, quietFill.count + 100,
                             "the state that stops every rule from firing put nothing on the "
                             + "page — \(banner) against \(quietFill)")
        let column = stuck.column
        XCTAssertEqual(banner.lowerBound, Int(column.minX.rounded()), accuracy: 1,
                       "the banner starts at \(banner.lowerBound) and every card at "
                       + "\(Int(column.minX)) — a filled field at a heading's inset")
        XCTAssertEqual(banner.upperBound, Int(column.maxX.rounded()) - 1, accuracy: 2,
                       "the banner ends at \(banner.upperBound) and every card at "
                       + "\(Int(column.maxX))")
    }

    /// And the rule's own row says it, which is the surface somebody looks at when
    /// a rule has stopped working. Measured on the rules card's height, the way the
    /// notice card's one refusal note is: the row grows by the note it draws.
    ///
    /// The rule in the harness points at «One», so it is exactly the rule whose
    /// tunnel is stuck — a note drawn under a rule pointing somewhere else would be
    /// the page inventing a problem, which is the second reading below.
    func testTheRuleRowSaysIt() {
        let quiet = rulesCardHeight(locked: [])
        let stuck = rulesCardHeight(locked: ["One"])
        XCTAssertGreaterThan(stuck, quiet,
                             "the row that cannot fire is \(stuck) pt and the working one "
                             + "\(quiet) pt: the rule says nothing about it")
        XCTAssertEqual(rulesCardHeight(locked: ["Another"]), quiet, accuracy: 0.5,
                       "a rule pointing at «One» drew a note about «Another»")
    }

    /// **One sentence per configuration, at the most specific place there is.**
    ///
    /// Photographed with both surfaces live: the identical sentence twice on one
    /// page, 230 pt apart — the duplication `VPNNotice.permissionMissing` exists to
    /// prevent one card lower down, and it was found by looking rather than by any
    /// of the readings above, each of which was green. So the row wins where there
    /// is a rule for that configuration, and the banner is what speaks for a
    /// configuration no rule covers: a rule deleted after the fact, or a keychain
    /// dialog somebody declined while connecting by hand.
    func testTheSentenceIsSaidOnceAndTheRulesRowWins() {
        let quiet = widestFillAboveTheFirstCard(locked: [], ruleFor: "One")
        let stuck = widestFillAboveTheFirstCard(locked: ["One"], ruleFor: "One")
        XCTAssertEqual(stuck.fill, quiet.fill,
                       "the banner said what the rule's own row is already saying 230 pt "
                       + "below it: \(String(describing: stuck.fill))")
        XCTAssertGreaterThan(rulesCardHeight(locked: ["One"]), rulesCardHeight(locked: []),
                             "precondition: the row is the one saying it — an equality above "
                             + "would otherwise pass on a page that says it nowhere")
    }

    // MARK: - The page, and the two instruments

    private func page(_ locked: [String], ruleFor vpn: String = "One") -> VPNSettingsPage {
        let transport = LocalTransport()
        // In memory, never `UserDefaults.standard`: this page writes its settings
        // through on every change.
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        // One rule, pointing at the one connection, so the section under the header
        // has a row drawn at its natural height.
        settings.setRulesJSON(VPNRules.encode([
            "com.apple.Safari": VPNAppRule(vpnName: vpn,
                                           identity: CodeIdentity(signingID: "com.apple.Safari",
                                                                  teamID: "APPLE"))]))
        let vm = VPNViewModel(transport: transport, settings: settings)
        var payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "id-One", name: "One", status: .disconnected,
                                        kind: "IPSec")],
            autoConnected: [], defaultName: nil, lastAutomation: nil)
        payload.secretsBehindAPrompt = locked
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: try! JSONEncoder().encode(payload)))
        pump { !vm.connections.isEmpty }
        XCTAssertEqual(vm.connections.count, 1,
                       "the wire did not deliver: nothing below measures anything")
        XCTAssertEqual(vm.secretsBehindAPrompt, locked, "…nor the state under test")
        return VPNSettingsPage(vm: vm, store: store)
    }

    /// Turns of the main run loop until `done`, or 80 of them — and therefore a
    /// **synchronous** test: driven from an `async` body this pumps nothing, and
    /// every reading comes back as the zero-connection empty state, which passes an
    /// assertion about a banner by having no page.
    private func pump(_ done: () -> Bool) {
        for _ in 0..<80 where !done() {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private static let width: CGFloat = 845
    /// Points ignored at each side of the rendering: the hosting view is 845 pt and
    /// the scrolling container inside it runs 50.5…794.5, so the 50 pt beside it is
    /// not the pane and reads as drawn from every row.
    private static let margin = 60

    private func mount(_ page: VPNSettingsPage) -> MountedRender {
        // Pinned light, like every other reading in this house: `NSApp`'s
        // appearance in a test process is whatever this Mac is set to this hour.
        let render = MountedRender(page, width: Self.width, height: 1500, appearance: .aqua)
        renders.append(render)
        render.settle(60)
        return render
    }

    private func sectionCards(_ render: MountedRender) -> [NSRect] {
        Set(render.host.everyView(named: "_NSGraphicsView").map(\.frame))
            .sorted { $0.minY < $1.minY }
    }

    private func rulesCardHeight(locked: [String]) -> CGFloat {
        let cards = sectionCards(mount(page(locked)))
        XCTAssertEqual(cards.count, 3,
                       "this page draws three section cards; found \(cards.count)")
        return cards.first?.height ?? 0
    }

    private func widestFillAboveTheFirstCard(locked: [String], ruleFor vpn: String)
        -> (fill: ClosedRange<Int>?, column: NSRect) {
        let render = mount(page(locked, ruleFor: vpn))
        let cards = sectionCards(render)
        XCTAssertFalse(cards.isEmpty, "no section card to line the banner up with")
        guard let card = cards.first else { return (nil, .zero) }
        // Into the host's own points, which is what the rendering is read in: the
        // settings column is centred in a wider window.
        let column = render.host.convert(card, from: card.superview(in: render.host))
        // Everything above the first card: the heading, the one connection card
        // (which stops at half the row by design, so the banner is the wider of the
        // two), the hint, and the banner if there is one.
        let band = 0...max(1, Int(column.minY) - 10)
        return (RenderedField.field(render.host, inPoints: band,
                                    paneAtX: Int(column.minX) - 8, margin: Self.margin),
                column)
    }
}

private extension NSRect {
    /// The view whose coordinate space this frame is in. A frame read off a subview
    /// means nothing without the space it was read in, and the section cards sit
    /// several containers down from the host.
    func superview(in root: NSView) -> NSView {
        // The last match, which is what the hand-written walk answered: it
        // overwrote `answer` on every hit rather than stopping at the first.
        root.everyViewWithAncestry.last { $0.view.frame == self }?.ancestry.last ?? root
    }
}
