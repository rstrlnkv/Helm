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
    private func page(_ connections: [VPNConnection],
                      notice: VPNNotice = .menuBar,
                      dropNotice: VPNNotice = .menuBar,
                      macOS: NoticeAuthorization = .authorized,
                      failure: VPNFailure? = nil) -> VPNSettingsPage {
        let transport = LocalTransport()
        // In memory, never `UserDefaults.standard`: this page writes its settings
        // through on every change.
        let store = NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore())
        let settings = VPNSettings(store: store)
        // One rule, so the section under the header has a row and its card is
        // drawn at its natural height.
        settings.setRulesJSON(VPNRules.encode(["com.apple.Safari": VPNAppRule(vpnName: "One")]))
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
        var found: Set<NSRect> = []
        walk(render.host) { view, _ in
            if "\(type(of: view))" == "_NSGraphicsView" { found.insert(view.frame) }
        }
        return found.sorted { $0.minY < $1.minY }
    }

    /// The focus rings of the controls drawn on the **bare pane** — outside every
    /// section card. On this page that is exactly the connection cards' verbs:
    /// the connections block rides on a section *header*, which is the one part
    /// of a grouped form drawn on the pane, and the header holds no other
    /// control. Left to right.
    private func verbs(_ render: MountedRender) -> [NSRect] {
        var found: [NSRect] = []
        walk(render.host) { view, insideCard in
            if "\(type(of: view))" == "_FocusRingView", !insideCard { found.append(view.frame) }
        }
        return found.sorted { $0.minX < $1.minX }
    }

    private func walk(_ view: NSView, _ visit: (NSView, Bool) -> Void) {
        func recurse(_ view: NSView, _ insideCard: Bool) {
            let card = insideCard || "\(type(of: view))" == "_NSGraphicsView"
            visit(view, insideCard)
            for sub in view.subviews { recurse(sub, card) }
        }
        recurse(view, false)
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
            let render = mount(page([connection("One", status)]))
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

    /// And the verb fills its card, which is what makes three of them line up.
    ///
    /// `.frame(maxWidth: .infinity)` on a macOS bordered *button* does not stretch
    /// it — the control hugs its title and centres itself, which is why the frame
    /// is on the label. Three cards then had three widths and two left edges: 74
    /// pt for «Connect», 100 for «Подключить». Measured here as a **ratio of the
    /// card**, so it stays true if the settings column moves: the card ceiling is
    /// half the row and the verb is that less 12 pt of padding on each side.
    func testThreeVerbsInARowShareOneWidthAndOneBaseline() {
        let render = mount(page([connection("One", .disconnected),
                                 connection("Two", .connecting),
                                 connection("Three", .connected)]))
        let rings = verbs(render)
        XCTAssertEqual(rings.count, 3, "three connections, three verbs")

        let widths = rings.map(\.width)
        XCTAssertEqual(widths.min()!, widths.max()!, accuracy: 1,
                       "three verbs of three widths: \(widths) — a card wide enough for the "
                       + "verb is what the grid was for")
        let tops = rings.map(\.minY)
        XCTAssertEqual(tops.min()!, tops.max()!, accuracy: 0.5,
                       "the three verbs sit on \(Set(tops).count) baselines: \(tops)")
        // Each verb fills its own column rather than hugging its title: three
        // columns of a 704 pt row, less the 12 pt gutters and 12 pt of card
        // padding a side, is about 203. A title-sized button is 74…100.
        XCTAssertGreaterThan(widths.min()!, 150,
                             "the verbs are \(widths) pt wide, which is the width of their "
                             + "own words rather than of the card they are in")
    }

    // MARK: - One permission note per card

    /// **Both rows wanting a banner is still one question.** The notice card
    /// decides two events, each row asked macOS's refusal for itself, and choosing
    /// «System notification» for both and then revoking the permission drew the
    /// same sentence twice, 300 pt apart. Measured on the card's own height, which
    /// is the number the survey recorded going 285 → 423.
    ///
    /// Three readings, because the equality alone is worth nothing: a page that
    /// had stopped drawing the note at all would satisfy it.
    func testTheRefusedPermissionIsSaidOnceHoweverManyRowsWantIt() {
        let quiet = noticeCardHeight(notice: .menuBar, dropNotice: .menuBar, macOS: .denied)
        let one = noticeCardHeight(notice: .system, dropNotice: .menuBar, macOS: .denied)
        let both = noticeCardHeight(notice: .system, dropNotice: .system, macOS: .denied)

        XCTAssertGreaterThan(one, quiet,
                            "precondition: a refused banner mode draws a note at all — "
                            + "\(one) against \(quiet)")
        XCTAssertEqual(both, one, accuracy: 0.5,
                       "the card is \(both) pt with both rows loud and \(one) pt with one: "
                       + "the same sentence twice")
    }

    /// …and macOS not having refused draws nothing, whatever the rows chose. `nil`
    /// is the state the page holds before its `.task` runs, and `.notDetermined`
    /// is a permission nobody has asked for — neither is a refusal, and a note
    /// drawn from one would accuse macOS of a denial it never made.
    func testAPermissionThatWasNeverRefusedDrawsNoNote() {
        let quiet = noticeCardHeight(notice: .menuBar, dropNotice: .menuBar, macOS: .denied)
        for answer in [NoticeAuthorization.authorized, .notDetermined] {
            XCTAssertEqual(noticeCardHeight(notice: .system, dropNotice: .system, macOS: answer),
                           quiet, accuracy: 0.5,
                           "a \(answer) permission drew the refusal note")
        }
    }

    /// The notice card is the second of the page's three: the per-app rules, the
    /// notice choices, the spin. Asserted rather than assumed, so a page that grew
    /// or lost a section fails here instead of measuring the wrong card.
    private func noticeCardHeight(notice: VPNNotice, dropNotice: VPNNotice,
                                  macOS: NoticeAuthorization) -> CGFloat {
        let render = mount(page([connection("One", .disconnected)],
                                notice: notice, dropNotice: dropNotice, macOS: macOS))
        let cards = sectionCards(render)
        XCTAssertEqual(cards.count, 3,
                       "this page draws three section cards; found \(cards.count)")
        return cards.count == 3 ? cards[1].height : 0
    }

    // MARK: - The refusal banner is in the cards' column

    /// **It has a fill, so it is a card.** The banner naming a command `scutil`
    /// would not accept lives in the section *header*, which a grouped form insets
    /// 10 pt further than the section's own card — right for a heading, which sits
    /// level with what the rows below *say*, and wrong for a filled field.
    /// Photographed before the fix: 30…713 against 20…723 for every card on the
    /// page.
    ///
    /// The banner's column comes from the rendering and the card's from AppKit, so
    /// the two sides of this equality are two different instruments.
    ///
    /// **The page with nothing refused is read first**, and it is the control: the
    /// widest fill above the first card is then the connection card itself, which
    /// stops at half the row. So «a wider fill has appeared» is what says the
    /// banner is on the page at all — an alignment assertion on a page that draws
    /// no banner would otherwise be measuring the connection card against a card,
    /// which is true and says nothing.
    func testTheRefusalBannerSharesTheCardsColumn() {
        let quiet = widestFillAboveTheFirstCard(failure: nil)
        let refused = widestFillAboveTheFirstCard(
            failure: VPNFailure(name: "One", reason: .noSuchService, verb: .connect))
        guard let quietFill = quiet.fill, let banner = refused.fill else {
            return XCTFail("nothing filled was drawn above the first card at all: "
                           + "\(String(describing: quiet.fill)) / "
                           + "\(String(describing: refused.fill))")
        }
        XCTAssertGreaterThan(banner.count, quietFill.count + 100,
                             "precondition: the refusal put a wider field on the page than the "
                             + "single connection card — \(banner) against \(quietFill)")

        let column = refused.column
        XCTAssertEqual(banner.lowerBound, Int(column.minX.rounded()), accuracy: 1,
                       "the banner starts at \(banner.lowerBound) and every card at "
                       + "\(Int(column.minX)) — a filled field at a heading's inset")
        XCTAssertEqual(banner.upperBound, Int(column.maxX.rounded()) - 1, accuracy: 2,
                       "the banner ends at \(banner.upperBound) and every card at "
                       + "\(Int(column.maxX))")
    }

    private func widestFillAboveTheFirstCard(failure: VPNFailure?)
        -> (fill: ClosedRange<Int>?, column: NSRect) {
        let render = mount(page([connection("One", .disconnected)], failure: failure))
        let cards = sectionCards(render)
        XCTAssertFalse(cards.isEmpty, "no section card to line the banner up with")
        guard let card = cards.first else { return (nil, .zero) }
        // Into the host's own points, which is what the rendering is read in: the
        // settings column is centred in a wider window.
        let column = render.host.convert(card, from: card.superview(in: render.host))
        return (RenderedField.field(render.host, inPoints: bandAbove(column),
                                    paneAtX: Int(column.minX) - 8, margin: Self.margin),
                column)
    }

    /// Everything the page draws above its first section card, which is where the
    /// refusal banner lives — the heading, the connections grid, the hint, and the
    /// banner if there is one.
    ///
    /// A whole band rather than an offset, so the test carries no number about
    /// where the banner happens to sit. The connection card is a fill too and is
    /// found here as well — which is exactly what makes the control work: **one**
    /// connection, whose card stops at half the row by design, so the banner is
    /// the wider of the two and «wider than the control» is the reading that says
    /// it was drawn.
    private func bandAbove(_ column: NSRect) -> ClosedRange<Int> {
        0...max(1, Int(column.minY) - 10)
    }

    /// Points ignored at each side of the rendering. The hosting view is 845 pt
    /// and the scrolling container inside it runs 50.5…794.5, so the 50 pt beside
    /// it is not the pane and reads as drawn from every row — which is how the
    /// first version of this test found one 765 pt «field» on every page it
    /// photographed, including the ones with no banner at all.
    private static let margin = 60
}

private extension NSRect {
    /// The view whose coordinate space this frame is in, found by matching it in
    /// the tree under `root`. A frame read off a subview means nothing without
    /// the space it was read in, and the section cards sit several containers
    /// down from the host.
    func superview(in root: NSView) -> NSView {
        var answer = root
        func recurse(_ view: NSView) {
            for sub in view.subviews {
                if sub.frame == self { answer = view }
                recurse(sub)
            }
        }
        recurse(root)
        return answer
    }
}
