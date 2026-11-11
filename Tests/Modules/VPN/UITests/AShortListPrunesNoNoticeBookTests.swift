// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// `scutil` answers with a short list or none at all on a refusal or a Mac
/// mid-boot, and the state that carries it reaches the model like any other. The
/// per-connection choices (`VPNNoticeBook`) are keyed by a configuration's id and
/// are the person's: a list that came back empty once is not a list of
/// configurations that were deleted. Defect class kept: the notice book pruned
/// against a short read.
@MainActor
final class AShortListPrunesNoNoticeBookTests: XCTestCase {

    func testAnEmptyListLeavesEveryChoiceInTheBook() async {
        let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                          backing: InMemoryKeyValueStore()))
        settings.setNoticeBook(settings.noticeBook.setting("1", notice: .silent))
        let before = VPNNoticeBook.encode(settings.noticeBook)
        XCTAssertNotEqual(before, VPNNoticeBook.encode(VPNNoticeBook()),
                          "precondition: the book holds a choice")

        let work = FakeVPNWork()
        let model = VPNViewModel(work: work, settings: settings)
        work.say(VPNEngine.StatePayload(connections: [], autoConnected: [],
                                        lastAutomation: nil))
        // The control: a later state with another configuration does arrive.
        work.say(VPNEngine.StatePayload(
            connections: [VPNConnection(id: "2", name: "Home", status: .disconnected,
                                        kind: "IKEv2")],
            autoConnected: [], lastAutomation: nil))
        await waitUntil("the second state arrives") { model.connections.map(\.id) == ["2"] }

        XCTAssertEqual(VPNNoticeBook.encode(settings.noticeBook), before,
                       "a short list changed the notice book")
        model.stop()
    }
}
