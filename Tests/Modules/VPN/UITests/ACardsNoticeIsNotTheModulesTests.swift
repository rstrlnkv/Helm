// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A card says «this connection only», so it writes this connection only.**
///
/// The card's choice used to write its book entry *and* the module-wide
/// notice, which every other connection without an entry inherits: one
/// tunnel set to Nothing silenced the drop of the next. «None» is a book entry
/// with no value for the kind; an older payload has no `noticeBook` key at all
/// and decodes to an empty book, which inherits — today's behaviour.
@MainActor
final class ACardsNoticeIsNotTheModulesTests: XCTestCase {

    private func fixture() async -> (VPNViewModel, VPNSettings, FakeAutomationNotice) {
        let work = FakeVPNWork()
        let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                          backing: InMemoryKeyValueStore()))
        let port = FakeAutomationNotice(state: .authorized)
        let vm = VPNViewModel(work: work, settings: settings, notices: port)
        work.say(VPNEngine.StatePayload(
            connections: [("id-A", "Office"), ("id-B", "Home")].map {
                VPNConnection(id: $0.0, name: $0.1, status: .disconnected, kind: "IKEv2")
            },
            autoConnected: [], lastAutomation: nil))
        for _ in 0..<500 where vm.connections.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(vm.connections.count, 2, "the stream did not deliver")
        return (vm, settings, port)
    }

    func testSettingOneTunnelsDropToNothingLeavesTheOthersAndTheDefault() async {
        let (vm, settings, _) = await fixture()
        let moduleDrop = settings.dropNotice, moduleRules = settings.notice
        // What the card does: its book entry, then the permission question.
        settings.setNoticeBook(settings.noticeBook.setting("id-A", drop: .silent))
        await vm.choose(.silent)

        XCTAssertEqual(vm.notice(for: .dropped, on: "Office"), .silent)
        XCTAssertEqual(vm.notice(for: .dropped, on: "Home"), moduleDrop,
                       "another tunnel's drop was silenced by this card")
        XCTAssertNotEqual(vm.notice(for: .dropped, on: "Home"), .silent)
        XCTAssertEqual(settings.dropNotice, moduleDrop)
        XCTAssertEqual(settings.notice, moduleRules)
    }

    func testAnOlderPayloadWithoutABookBehavesAsItDid() async {
        let (vm, settings, _) = await fixture()
        settings.store.set(VPNNotice.system.rawValue, for: VPNSettings.dropNoticeKey)
        XCTAssertNil(settings.store.object("noticeBook"))
        XCTAssertEqual(vm.notice(for: .dropped, on: "Office"), .system)
        XCTAssertEqual(vm.notice(for: .dropped, on: "Home"), .system)
    }
}
