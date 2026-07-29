// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmContract
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// A rule fired by itself, and the person is told — or is not.
///
/// This is the trap Task 8 left standing on purpose. `.system` suppresses the
/// menu-bar label because the banner is supposed to carry the name, so writing
/// the authorization mirror before wiring the banner turns the loudest mode
/// into the silent one. The invariant below is structural — *some* channel
/// carries the firing — rather than a check on one of them, because it is
/// exactly the "both were switched off" state that shipped once.
@MainActor
final class VPNAutomationAnnouncementTests: XCTestCase {

    private func firing(name: String = "Office",
                        kind: VPNAutomation.Kind = .connected) -> VPNAutomation {
        VPNAutomation(at: Date(), name: name, kind: kind)
    }

    private func emit(_ automation: VPNAutomation, on transport: LocalTransport) {
        let payload = VPNEngine.StatePayload(
            connections: [VPNConnection(id: "A1", name: "Office",
                                        status: .connected, kind: "IKEv2")],
            autoConnected: ["Office"], defaultName: "Office", lastAutomation: automation)
        transport.emit(EngineEvent(name: "state",
                                   payload: try! JSONEncoder().encode(payload)))
    }

    /// Waits on the firing itself: the assertion is only reached once the very
    /// payload carrying it has been handled, so nothing here passes by being
    /// asked before the work happened.
    private func settle(_ model: VPNViewModel, _ port: FakeAutomationNotice) async {
        for _ in 0..<500 where model.lastAutomation == nil || port.posted.isEmpty {
            await Task.yield()
        }
    }

    /// One object answers both questions, because the defect is that the two
    /// answers can both be "nothing" at the same time.
    private func announce(notice: VPNNotice, authorized: Bool)
        async -> (banner: [(String, String)], label: String?) {
        let transport = LocalTransport()
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: transport)
        let port = FakeAutomationNotice()
        let model = descriptor.viewModel(host)
        model.setForTesting(automation: nil, notice: notice,
                            bannerAuthorized: authorized, notices: port)
        emit(firing(), on: transport)
        await settle(model, port)
        return (port.posted, descriptor.statusAppearance(host).title)
    }

    func testTheAuthorizedBannerModePostsTheBanner() async {
        let said = await announce(notice: .system, authorized: true)
        XCTAssertEqual(said.banner.count, 1, "the mode that asks to be told loudly said nothing")
        XCTAssertTrue(said.banner[0].1.contains("Office"),
                      "the banner did not name the connection: \(said.banner)")
    }

    /// The defect in one assertion: a firing the person asked to hear about
    /// must leave by one door or the other, never by neither.
    func testEveryModeThatSpeaksAtAllSpeaksExactlyOnce() async {
        for authorized in [true, false] {
            for notice in [VPNNotice.menuBar, .system] {
                let said = await announce(notice: notice, authorized: authorized)
                let banner = !said.banner.isEmpty
                let label = said.label != nil
                XCTAssertTrue(banner || label,
                              "\(notice), authorized: \(authorized) — the rule fired and "
                              + "neither the banner nor the menu bar said so")
                XCTAssertFalse(banner && label,
                               "\(notice), authorized: \(authorized) — said twice; the "
                               + "banner carries the name so the label steps aside")
            }
        }
    }

    /// Chosen silence stays silent. The ring still turns, which is the
    /// descriptor's business and `VPNStatusAppearanceTests`'s.
    func testTheSilentModePostsNothingAndNamesNothing() async {
        let said = await announce(notice: .silent, authorized: true)
        XCTAssertTrue(said.banner.isEmpty)
        XCTAssertNil(said.label)
    }

    /// The engine keeps its last firing for good and repeats it in every state
    /// payload — a refresh while the name is still on screen must not post the
    /// banner again.
    func testARepeatedPayloadDoesNotPostTheBannerTwice() async {
        let transport = LocalTransport()
        let port = FakeAutomationNotice()
        let model = VPNViewModel(transport: transport, notices: port)
        model.setForTesting(automation: nil, notice: .system, bannerAuthorized: true)
        let fired = firing()
        emit(fired, on: transport)
        await settle(model, port)
        emit(fired, on: transport)
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(port.posted.count, 1, "the same firing was announced twice")
    }
}
