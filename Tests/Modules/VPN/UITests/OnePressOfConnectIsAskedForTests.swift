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
/// **One surface, and it used to be two.** The banner spoke for the configurations
/// no rule covered and each rule's own row spoke for the rest, which is why
/// `VPNRules.unspokenFor` existed. The rules live behind a door on their card now,
/// so that row is invisible until somebody opens a popover — and a configuration
/// that cannot raise its tunnel said so nowhere at all. Measured here as «the page
/// grows a news card, once per locked configuration».
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

    // MARK: - The page says it

    /// **The news card appears, and it is what the sentence is drawn in.**
    ///
    /// **The page's one section is its news, so with nothing to say it draws no
    /// card at all** — every setting is on a card or behind its doors. Counted in
    /// AppKit frames rather than pixels, so «the page grew a card» is a number and
    /// not an inference from colour, and the quiet page is the control: a page that
    /// had stopped drawing the sentence fails here rather than passing an alignment
    /// nobody drew.
    func testALockedConfigurationPutsANewsCardOnThePage() {
        XCTAssertEqual(sectionCards(mount(page([]))).count, 0,
                       "with nothing to say the page draws no section card")
        XCTAssertEqual(sectionCards(mount(page(["One"]))).count, 1,
                       "a locked configuration drew no news card")
    }

    /// **And it says it however many rules point at that configuration.** This is
    /// the regression the door cost: `unspokenFor` removed a configuration a rule
    /// covered, on the strength of a row 230 pt below — a row that is inside a
    /// popover now. Both fixtures have a rule; one points at the locked
    /// configuration and one somewhere else, and the sentence has to survive both.
    func testTheRuleBehindTheDoorDoesNotSilenceThePage() {
        for pointedAt in ["One", "Other"] {
            let quiet = newsCardHeight(locked: [], ruleFor: pointedAt)
            let stuck = newsCardHeight(locked: ["One"], ruleFor: pointedAt)
            XCTAssertGreaterThan(stuck, quiet,
                                 "with the rule pointing at «\(pointedAt)» the page grew "
                                 + "\(stuck) against \(quiet): the sentence is nowhere")
        }
    }

    /// One sentence per configuration, and the increment says so: a second locked
    /// configuration adds exactly the height of the first sentence.
    ///
    /// **Both fixtures keep the rule pointing at «One».** A rule pointing anywhere
    /// else is a rule pointing at a configuration this Mac does not have, which is
    /// its own sentence in the same card — measured at 107 pt against 54 while this
    /// test was being written, and read for a moment as the page saying the locked
    /// one twice.
    func testEachLockedConfigurationIsNamedOnce() {
        let one = newsCardHeight(locked: ["One"], ruleFor: "One")
        let two = newsCardHeight(locked: ["One", "Two"], ruleFor: "One")
        XCTAssertLessThan(one, 80,
                          "one locked configuration drew \(one) pt, which is two rows: the same "
                          + "sentence twice")
        XCTAssertEqual(two - one, one, accuracy: 6,
                       "a second locked configuration added \(two - one) pt where one sentence "
                       + "is \(one): it is not named, or it is named more than once")
    }

    /// **And the sentence is drawn inside that card's column.** It is a row of a
    /// section now rather than a view riding the header, which is what the header's
    /// 10 pt outset used to be backed out by hand for; a fill escaping the card is
    /// the defect that shape removes, so it is worth a photograph.
    ///
    /// Two instruments: the card's column is an AppKit frame, the fill is read off
    /// the rendering.
    func testTheSentenceIsDrawnInsideTheNewsCard() {
        let render = mount(page(["One"]))
        let cards = sectionCards(render)
        guard let card = cards.first else { return XCTFail("no news card was drawn") }
        let column = render.host.convert(card, from: card.superview(in: render.host))
        guard let fill = RenderedField.field(render.host,
                                            inPoints: (Int(column.minY) + 2)...(Int(column.maxY) - 2),
                                            paneAtX: Int(column.minX) - 8,
                                            margin: Self.margin) else {
            return XCTFail("nothing was drawn inside the news card at all")
        }
        XCTAssertGreaterThan(fill.count, 400,
                            "the widest field in the news card is \(fill.count) pt — a banner "
                            + "spans its row, so this is measuring something else")
        XCTAssertGreaterThanOrEqual(fill.lowerBound, Int(column.minX.rounded()) - 1,
                                    "the sentence starts at \(fill.lowerBound), left of the card "
                                    + "at \(Int(column.minX)) — a filled field at a heading's inset")
        XCTAssertLessThanOrEqual(fill.upperBound, Int(column.maxX.rounded()) + 1,
                                 "the sentence ends at \(fill.upperBound), right of the card at "
                                 + "\(Int(column.maxX))")
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

    /// The height of everything the page has to say. **Zero is a real answer**:
    /// the news is the page's only section, so a page with nothing to say draws no
    /// card — which is what makes «it grew» a reading rather than a comparison of
    /// two heights that might both be of the wrong card.
    private func newsCardHeight(locked: [String], ruleFor vpn: String) -> CGFloat {
        sectionCards(mount(page(locked, ruleFor: vpn))).first?.height ?? 0
    }
}
