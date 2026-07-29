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

    /// Waits on the announcement itself rather than on a count of yields: the
    /// firing arrives on the event loop, and everything the assertions read is
    /// written by the task that handles it. A number of yields would be a race
    /// that happens to come out right, which is the way a broken fix shipped
    /// green here once already.
    private func settle(_ model: VPNViewModel) async {
        for _ in 0..<500 where model.lastAutomation == nil { await Task.yield() }
        await model.announcement?.value
    }

    /// One object answers both questions, because the defect is that the two
    /// answers can both be "nothing" at the same time.
    ///
    /// `mirror` is what the settings page last wrote down and `macOS` is what
    /// the system would answer if asked now. They are separate parameters
    /// because the two disagree the moment someone revokes the permission in
    /// System Settings, and the app hears nothing when they do.
    private func announce(notice: VPNNotice, mirror: Bool, macOS: NoticeAuthorization)
        async -> (banner: [(String, String)], label: String?) {
        let transport = LocalTransport()
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: transport)
        let port = FakeAutomationNotice(state: macOS)
        let model = descriptor.viewModel(host)
        model.setForTesting(automation: nil, notice: notice,
                            bannerAuthorized: mirror, notices: port)
        emit(firing(), on: transport)
        await settle(model)
        return (port.posted, descriptor.statusAppearance(host).title)
    }

    func testTheAuthorizedBannerModePostsTheBanner() async {
        let said = await announce(notice: .system, mirror: true, macOS: .authorized)
        XCTAssertEqual(said.banner.count, 1, "the mode that asks to be told loudly said nothing")
        XCTAssertTrue(said.banner[0].1.contains("Office"),
                      "the banner did not name the connection: \(said.banner)")
    }

    /// The defect in one assertion: a firing the person asked to hear about
    /// must leave by one door or the other, never by neither.
    ///
    /// Every mode against every answer macOS can give, with the stored mirror
    /// deliberately holding the opposite — the state left behind by a
    /// permission revoked in System Settings since the page was last open. A
    /// firing decided on that memory is decided wrong, and `.system` is the
    /// mode where wrong means silence: it hides the menu-bar name because the
    /// banner is meant to carry it, and macOS drops the banner.
    func testEveryModeThatSpeaksAtAllSpeaksExactlyOnce() async {
        for macOS in [NoticeAuthorization.authorized, .denied, .notDetermined] {
            for notice in VPNNotice.allCases {
                let said = await announce(notice: notice, mirror: macOS != .authorized,
                                          macOS: macOS)
                let banner = !said.banner.isEmpty
                let label = said.label != nil
                let where_ = "\(notice), macOS says \(macOS)"
                guard notice != .silent else {
                    XCTAssertFalse(banner || label, "\(where_) — silence was chosen and broken")
                    continue
                }
                XCTAssertTrue(banner || label,
                              "\(where_) — the rule fired and neither the banner nor the "
                              + "menu bar said so")
                XCTAssertFalse(banner && label,
                               "\(where_) — said twice; the banner carries the name so the "
                               + "label steps aside")
                XCTAssertEqual(banner, notice == .system && macOS == .authorized,
                               "\(where_) — the banner was decided on the stored mirror "
                               + "rather than on what macOS says now")
            }
        }
    }

    /// Chosen silence stays silent. The ring still turns, which is the
    /// descriptor's business and `VPNStatusAppearanceTests`'s.
    func testTheSilentModePostsNothingAndNamesNothing() async {
        let said = await announce(notice: .silent, mirror: true, macOS: .authorized)
        XCTAssertTrue(said.banner.isEmpty)
        XCTAssertNil(said.label)
    }

    /// The measured defect, on its own: the permission was revoked in System
    /// Settings and nobody has opened the VPN page since, so the only record
    /// the app holds says yes. The firing must still reach the person.
    func testARevokedPermissionIsNoticedWhenTheRuleFiresAndNotAtTheNextSettingsVisit() async {
        let said = await announce(notice: .system, mirror: true, macOS: .denied)
        XCTAssertTrue(said.banner.isEmpty, "macOS had refused, so nothing was shown")
        XCTAssertEqual(said.label, "Office",
                       "the ring turned and nothing was named — the silence the fallback exists "
                       + "to prevent, on the strength of a stale yes")
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
        await settle(model)
        emit(fired, on: transport)
        for _ in 0..<200 { await Task.yield() }
        await model.announcement?.value
        XCTAssertEqual(port.posted.count, 1, "the same firing was announced twice")
    }
}
