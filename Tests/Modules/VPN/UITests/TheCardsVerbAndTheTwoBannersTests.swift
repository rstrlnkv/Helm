// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The three places on this page that nobody was looking at.
///
/// The v3 survey of 2026-08-11 listed twelve findings and closed with what the
/// tools could not see: «no pixel tests on the refusal banner, the double banner
/// or the button width while connecting — the apparatus is already in that
/// folder». All three were live defects, and all three were fixed by reading. So
/// this file measures them, and it measures two of the three **exactly** rather
/// than in pixels: SwiftUI backs a grouped `Form`'s section card with an
/// `_NSGraphicsView` and a bordered control with a `_FocusRingView`, and an
/// AppKit frame is a number rather than an inference from colour.
///
/// The banner is the one that has no frame — a rounded fill drawn into its
/// parent's layer — so `RenderedField` reads its column off the rendering, and
/// compares it against the *card's own* AppKit frame. Two instruments, so
/// neither is checked against itself.
@MainActor
final class TheCardsVerbAndTheTwoBannersTests: XCTestCase {

    // MARK: - The page, with the state each test needs

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private func connection(_ name: String, _ status: VPNStatus) -> VPNConnection {
        VPNConnection(id: "id-\(name)", name: name, status: status, kind: "IKEv2")
    }

    /// A page with the connections, notice modes and failure a test needs — and a
    /// **fake notification centre**, because `vm.bannerAuthorization` is the value
    /// the permission note is decided from and nothing else in the model can set
    /// it. `nil` there is «nobody has asked macOS this launch», which is a
    /// different state from a refusal and draws no note at all: a test that let it
    /// stay nil would be measuring a page with no note in it and calling the
    /// absence a pass.
    /// - Parameter rules: whether the page has any per-app rules at all.
    ///   **The verb tests below say no**, and that is not tidiness: with rules
    ///   the heading carries an «Edit» button, which is a focus ring outside a
    ///   graphics view exactly as a card's verb is, and `verbs(_:)` would count
    ///   it. The count in those tests is what caught it — measured, the second
    ///   ring was (660, 143, 54×14) against the verb's (326, 54.5, 28×28).
    private func page(_ connections: [VPNConnection],
                      notice: VPNNotice = .menuBar,
                      dropNotice: VPNNotice = .menuBar,
                      macOS: NoticeAuthorization = .authorized,
                      rules: Bool = true,
                      failure: VPNFailure? = nil) -> VPNSettingsPage {
        let transport = LocalTransport()
        // In memory, never `UserDefaults.standard`: this page writes its settings
        // through on every change.
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        // One rule, so the section under the header has a row and its card is
        // drawn at its natural height.
        if rules {
            settings.setRulesJSON(VPNRules.encode(["com.apple.Safari":
                                                    VPNAppRule(vpnName: "One")]))
        }
        settings.setNotice(notice)
        settings.setDropNotice(dropNotice)
        let vm = VPNViewModel(transport: transport, settings: settings,
                              notices: FakeAutomationNotice(state: macOS))
        var payload = VPNEngine.StatePayload(connections: connections, autoConnected: [],
                                            defaultName: nil, lastAutomation: nil)
        payload.lastFailure = failure
        transport.emit(EngineEvent(name: "state",
                                   payload: try! JSONEncoder().encode(payload)))
        pump { !vm.connections.isEmpty }
        // The page's own `.task` does this in the app. Driven here rather than
        // waited for, so the reading is of a settled state.
        Task { await vm.refreshBannerAuthorization() }
        pump { vm.bannerAuthorization != nil }
        XCTAssertEqual(vm.connections.count, connections.count,
                       "the wire did not deliver: nothing below measures anything")
        return VPNSettingsPage(vm: vm, store: store)
    }

    /// Turns of the main run loop until `done`, or 80 of them. `RunLoop.current`
    /// and not `Task.yield`, and therefore a **synchronous** test: driven from an
    /// `async` test body this pumps nothing at all, and every reading below came
    /// back as the zero-connection empty state — which passes an assertion about
    /// two banners by having neither.
    private func pump(_ done: () -> Bool) {
        for _ in 0..<80 where !done() {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    private static let width: CGFloat = 845

    private func mount(_ page: VPNSettingsPage, height: CGFloat = 1500) -> MountedRender {
        // Pinned light, like every other reading in this house: `NSApp`'s
        // appearance in a test process is whatever this Mac is set to this hour.
        let render = MountedRender(page, width: Self.width, height: height, appearance: .aqua)
        renders.append(render)
        render.settle(60)
        return render
    }

    // MARK: - Reading the frames SwiftUI does back with a view

    /// The grouped form's section cards, top to bottom. Every *row* of a section
    /// is backed by a view carrying the **section's** frame, so the distinct
    /// frames are the cards.
    private func sectionCards(_ render: MountedRender) -> [NSRect] {
        Set(render.host.everyView(named: "_NSGraphicsView").map(\.frame))
            .sorted { $0.minY < $1.minY }
    }

    /// The focus rings of the controls drawn on the **bare pane** — outside every
    /// section card. On this page that is exactly the connection cards' verbs:
    /// the connections block rides on a section *header*, which is the one part
    /// of a grouped form drawn on the pane, and the header holds no other
    /// control. Left to right.
    private func verbs(_ render: MountedRender) -> [NSRect] {
        // «Outside a card» is a fact about what is *above* this view, which is
        // why the walk cannot be a filter over a flat list — `everyViewWithAncestry`
        // is the shared walk that still carries it.
        render.host.everyViewWithAncestry
            .filter { $0.view.appKitClassName == "_FocusRingView" }
            .filter { !$0.ancestry.contains { $0.appKitClassName == "_NSGraphicsView" } }
            // **And not the rules.** They are a `List` now — one flat sequence,
            // because `.onMove` cannot cross a `Section` — so every control in a
            // rule's row is inside an `NSTableRowView`, and each of them is a
            // focus ring outside a graphics view exactly as a card's verb is.
            // Before the rules moved into a table this filter found one view and
            // the count below said so; the count is what caught it.
            .filter { !$0.ancestry.contains { $0.appKitClassName.contains("TableRow") } }
            .map(\.view.frame)
            // **And the verb is the round one.** A card carries three controls
            // now — the verb, and the two doors under the divider — and all three
            // are focus rings on the bare pane. The verb is the only circle:
            // `VPNConnectionCard` draws it 28×28 and gives both doors a fixed
            // height with the width their contents ask for. Counted rather than
            // assumed: with three rings a card, every reading below would have
            // been of a door.
            .filter { abs($0.width - $0.height) < 1 }
            .sorted { $0.minX < $1.minX }
    }

    /// The doors: the other two rings on a card, left to right. One height by
    /// construction — `VPNConnectionCard.doorHeight` is on the container — and this
    /// is the reading that says so on the screen rather than in the source.
    private func doors(_ render: MountedRender) -> [NSRect] {
        render.host.everyViewWithAncestry
            .filter { $0.view.appKitClassName == "_FocusRingView" }
            .filter { !$0.ancestry.contains { $0.appKitClassName == "_NSGraphicsView" } }
            .filter { !$0.ancestry.contains { $0.appKitClassName.contains("TableRow") } }
            .map(\.view.frame)
            .filter { abs($0.width - $0.height) >= 1 }
            .sorted { $0.minX < $1.minX }
    }

    // MARK: - The verb does not move when a tunnel comes up

    /// **The defect this replaces was measured at 22 pt on the one control the
    /// person was reaching for.** A spinner shared the button's `HStack`, so a
    /// card that started connecting took its button from 202.5 pt to 181.0 and
    /// slid its left edge — and the same button was `.disabled` for every
    /// transition, so a tunnel hung on «connecting» left a card with nothing to
    /// press. Both were fixed by reading, and neither had a test.
    ///
    /// The frame is read for all five statuses at once, so the invariant is «the
    /// verb occupies the same rectangle whatever the tunnel is doing» rather than
    /// one pair of numbers.
    func testTheVerbKeepsItsRectangleThroughEveryStatus() {
        var seen: [VPNStatus: NSRect] = [:]
        for status in [VPNStatus.disconnected, .connecting, .connected, .disconnecting, .unknown] {
            let render = mount(page([connection("One", status)], rules: false))
            let rings = verbs(render)
            XCTAssertEqual(rings.count, 1,
                           "\(status): one connection draws one verb, not \(rings.count) — "
                           + "the reading below would be of something else")
            seen[status] = rings.first ?? .zero
        }
        let disconnected = try? XCTUnwrap(seen[.disconnected])
        XCTAssertNotNil(disconnected)
        for (status, frame) in seen where status != .disconnected {
            XCTAssertEqual(frame.minX, seen[.disconnected]!.minX, accuracy: 0.5,
                           "\(status) moved the verb's left edge to \(frame.minX)")
            XCTAssertEqual(frame.width, seen[.disconnected]!.width, accuracy: 1,
                           "\(status) resized the verb to \(frame.width) pt")
        }
    }

    /// And the verbs in one row line up.
    ///
    /// **What this used to assert is deliberately gone.** The verb was a word
    /// stretched to the card's width — `.frame(maxWidth: .infinity)` on the
    /// *label*, because a macOS bordered button does not stretch — and the test
    /// held that width as a ratio of the card. The card is a row now and the
    /// verb is a glyph with its word in the tooltip and in the VoiceOver label
    /// (`VPNCardGlyph`, `TheCardWearsAGlyphThatExistsTests`), so a verb as wide
    /// as its card would be a 300 pt button around a 13 pt mark.
    ///
    /// What survives is the invariant that was worth having: the verbs in one
    /// row are one size and one baseline, whatever shape they are. Two of them,
    /// because two is what a row holds now.
    func testTheVerbsInOneRowShareOneWidthAndOneBaseline() {
        let render = mount(page([connection("One", .disconnected),
                                 connection("Two", .connecting)], rules: false))
        let rings = verbs(render)
        XCTAssertEqual(rings.count, 2, "two connections, two verbs")

        let widths = rings.map(\.width)
        XCTAssertEqual(widths.min()!, widths.max()!, accuracy: 1,
                       "two verbs of two widths: \(widths) — «Cancel» and «Connect» are "
                       + "different words and must not be different buttons")
        let tops = rings.map(\.minY)
        XCTAssertEqual(tops.min()!, tops.max()!, accuracy: 0.5,
                       "the verbs sit on \(Set(tops).count) baselines: \(tops)")
    }

    /// **The two doors are one height.** Each used to be sized by what was inside
    /// it — four application icons on the left, one glyph on the right — so the
    /// applications door stood taller than the notices door beside it on every
    /// card. `doorHeight` is on the container now, and this is the measurement of
    /// that: one connection, two doors, one height and one baseline.
    func testTheTwoDoorsAreOneHeightAndOneBaseline() {
        let render = mount(page([connection("One", .disconnected)], rules: false))
        let leaves = doors(render)
        XCTAssertEqual(leaves.count, 2,
                       "a card has two doors; found \(leaves.count) — the reading below would be "
                       + "of something else")
        guard leaves.count == 2 else { return }
        XCTAssertEqual(leaves[0].height, leaves[1].height, accuracy: 0.5,
                       "the applications door is \(leaves[0].height) pt and the notices door "
                       + "\(leaves[1].height): two sizes of the same control")
        XCTAssertEqual(leaves[0].minY, leaves[1].minY, accuracy: 0.5,
                       "the doors sit on two baselines: \(leaves[0].minY) and \(leaves[1].minY)")
    }

    /// And a door full of icons is still that height. The defect was a door sized
    /// by its contents, so the reading that catches it is the same card with four
    /// applications behind the left door and none behind the right.
    func testADoorFullOfApplicationsIsStillOneHeight() {
        let render = mount(page([connection("One", .disconnected)], rules: true))
        let leaves = doors(render)
        XCTAssertEqual(leaves.count, 2, "a card has two doors; found \(leaves.count)")
        guard leaves.count == 2 else { return }
        XCTAssertEqual(leaves[0].height, leaves[1].height, accuracy: 0.5,
                       "with a rule behind it the applications door is \(leaves[0].height) pt "
                       + "against the notices door's \(leaves[1].height)")
    }

    // MARK: - One permission note per card

    /// **Both questions wanting a banner is still one question — and the card is
    /// where it is asked now.** The page used to draw the two notice choices for
    /// the whole module, each asking macOS's refusal for itself: choosing «System
    /// notification» for both events and then revoking the permission drew the
    /// same sentence twice, 300 pt apart, and took that card from 285 to 423 pt.
    /// The choices are in a per-connection popover now.
    ///
    /// **A popover cannot be photographed off screen** — it is a window macOS
    /// orders in, and this bench has no window server. So the claim is held in two
    /// halves that cannot both be true of a page that says it twice: the question
    /// is `VPNNotice.permissionMissing` over **both** modes, measured here for
    /// every combination, and the source draws the note from that question exactly
    /// once.
    func testTheRefusedPermissionIsOneQuestionOverBothModes() {
        for (rules, drop) in [(VPNNotice.system, VPNNotice.system),
                              (.system, .menuBar), (.menuBar, .system)] {
            XCTAssertTrue(VPNNotice.permissionMissing(among: [rules, drop],
                                                      authorization: .denied),
                          "\(rules)/\(drop): a refused banner mode was not noticed")
        }
        XCTAssertFalse(VPNNotice.permissionMissing(among: [.menuBar, .silent],
                                                   authorization: .denied),
                       "a note was drawn for two modes that need no permission")
    }

    /// …and a permission nobody refused draws nothing, whatever the modes are.
    /// `nil` is the state the card holds before the page's `.task` runs, and
    /// `.notDetermined` is a permission nobody has asked for — a note from either
    /// accuses macOS of a denial it never made.
    func testAPermissionThatWasNeverRefusedIsNotAMissingOne() {
        for answer in [NoticeAuthorization.authorized, .notDetermined, nil] {
            XCTAssertFalse(VPNNotice.permissionMissing(among: [.system, .system],
                                                       authorization: answer),
                           "a \(String(describing: answer)) permission was read as a refusal")
        }
    }

    /// The other half: one note, drawn from that one question, and drawn where the
    /// modes are chosen. A source reading rather than a rendering, because the
    /// surface is a popover — and it is the reading that fails if somebody puts the
    /// note back on each of the two choices.
    func testTheNoteIsDrawnOnceFromThatOneQuestion() throws {
        let card = RepoSource.root
            .appendingPathComponent("Sources/Modules/VPN/UI/VPNConnectionCard.swift")
        let source = try String(contentsOf: card, encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: "HelmPermissionNote").count - 1, 1,
                       "the refusal note is drawn more than once on one card")
        XCTAssertTrue(source.contains("permissionMissing(among: [notice, dropNotice]"),
                      "the note is not drawn from the question that folds both modes into one")
        let module = RepoSource.root.appendingPathComponent("Sources/Modules/VPN")
        let elsewhere = try FileManager.default
            .subpathsOfDirectory(atPath: module.path)
            .filter { $0.hasSuffix(".swift") && !$0.hasSuffix("VPNConnectionCard.swift") }
            .filter { (try? String(contentsOf: module.appendingPathComponent($0),
                                   encoding: .utf8))?.contains("HelmPermissionNote") == true }
        XCTAssertEqual(elsewhere, [],
                       "the module draws the refusal note somewhere other than the popover the "
                       + "modes are chosen in: \(elsewhere)")
    }

    // MARK: - The refusal banner is a row in the news card

    /// **It has a fill, so it is a row.** The banner naming a command `scutil` would
    /// not accept used to live in the section *header*, which a grouped form insets
    /// 10 pt further than the section's own card — right for a heading, which sits
    /// level with what the rows below say, and wrong for a filled field.
    /// Photographed before that fix: 30…713 against 20…723 for every card on the
    /// page, and the fix was a hand-written negative inset. It is a row of the
    /// section now, which is what a row is for.
    ///
    /// Three readings: the refusal grows a card the quiet page does not have, the
    /// fill inside it spans a row, and it stays inside the card's own column. The
    /// column is an AppKit frame and the fill is read off the rendering, so neither
    /// instrument is checked against itself.
    func testTheRefusalBannerIsARowInsideTheCardsColumn() {
        XCTAssertEqual(sectionCards(mount(page([connection("One", .disconnected)]))).count, 0,
                       "with nothing refused the page has nothing to say and draws no card")

        let render = mount(page([connection("One", .disconnected)],
                                failure: VPNFailure(name: "One", reason: .noSuchService,
                                                    verb: .connect)))
        let cards = sectionCards(render)
        XCTAssertEqual(cards.count, 1, "a refusal drew no news card")
        guard let card = cards.first else { return }
        // Into the host's own points, which is what the rendering is read in: the
        // settings column is centred in a wider window.
        let column = render.host.convert(card, from: card.superview(in: render.host))
        guard let fill = RenderedField.field(
            render.host, inPoints: (Int(column.minY) + 2)...(Int(column.maxY) - 2),
            paneAtX: Int(column.minX) - 8, margin: Self.margin) else {
            return XCTFail("nothing was drawn inside the news card at all")
        }
        XCTAssertGreaterThan(fill.count, 400,
                             "the widest field in the news card is \(fill.count) pt — a banner "
                             + "spans its row, so this is measuring something else")
        XCTAssertGreaterThanOrEqual(fill.lowerBound, Int(column.minX.rounded()) - 1,
                                    "the banner starts at \(fill.lowerBound), left of the card at "
                                    + "\(Int(column.minX)) — a filled field at a heading's inset")
        XCTAssertLessThanOrEqual(fill.upperBound, Int(column.maxX.rounded()) + 1,
                                 "the banner ends at \(fill.upperBound), right of the card at "
                                 + "\(Int(column.maxX))")
    }

    /// Points ignored at each side of the rendering. The hosting view is 845 pt
    /// and the scrolling container inside it runs 50.5…794.5, so the 50 pt beside
    /// it is not the pane and reads as drawn from every row — which is how the
    /// first version of this test found one 765 pt «field» on every page it
    /// photographed, including the ones with no banner at all.
    private static let margin = 60
}
