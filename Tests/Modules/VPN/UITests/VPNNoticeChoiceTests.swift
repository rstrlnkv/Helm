// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmContract
import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// Picking how loudly a firing is announced — the settings row's whole
/// behaviour, minus the view.
///
/// macOS shows the notification prompt once ever. An app that asks at launch,
/// or asks again on every visit to a settings page, spends that one chance on
/// somebody who was not asking for notifications, so *when* the question is put
/// is as much a part of this as what is stored.
@MainActor
final class VPNNoticeChoiceTests: XCTestCase {

    private func model(_ port: FakeAutomationNotice) -> (VPNViewModel, VPNSettings) {
        let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                          backing: InMemoryKeyValueStore()))
        return (VPNViewModel(transport: LocalTransport(), settings: settings, notices: port),
                settings)
    }

    func testAQuietModeIsStoredWithoutAskingMacOSAnything() async {
        let port = FakeAutomationNotice()
        let (vm, settings) = model(port)
        await vm.choose(.menuBar)
        XCTAssertEqual(settings.notice, .menuBar)
        XCTAssertEqual(port.requests, 0, "macOS was asked for a permission nobody needed")
    }

    /// The one place in the app that may ask, and it asks once.
    func testTheBannerModeAsksMacOSAndRemembersTheAnswer() async {
        let port = FakeAutomationNotice(state: .authorized)
        let (vm, settings) = model(port)
        await vm.choose(.system)
        XCTAssertEqual(port.requests, 1)
        XCTAssertEqual(settings.notice, .system)
        XCTAssertTrue(settings.bannerAuthorized, "macOS said yes and the mirror did not hear it")
        XCTAssertEqual(vm.effectiveNotice, .system)
    }

    /// A refusal must not leave the loudest mode silent: the label takes over,
    /// and the page has something to say about why.
    func testARefusalIsRememberedAndFallsBackToTheLabel() async {
        let port = FakeAutomationNotice(state: .denied)
        let (vm, settings) = model(port)
        await vm.choose(.system)
        XCTAssertFalse(settings.bannerAuthorized)
        XCTAssertEqual(vm.bannerAuthorization, .denied,
                       "the page has no way to tell the person macOS refused")
        XCTAssertEqual(vm.effectiveNotice, .menuBar,
                       "a refused banner became silence rather than the menu-bar name")
    }

    /// The mirror is what `.system` is judged against for the rest of the
    /// app's life, so a permission revoked in System Settings has to be able to
    /// come back down — by reading, which prompts nobody, never by asking.
    func testTheMirrorIsCorrectedByAReadThatPromptsNobody() async {
        let port = FakeAutomationNotice(state: .authorized)
        let (vm, settings) = model(port)
        await vm.choose(.system)
        XCTAssertTrue(settings.bannerAuthorized)

        let revoked = FakeAutomationNotice(state: .denied)
        let (vm2, settings2) = model(revoked)
        await vm2.choose(.system)
        XCTAssertFalse(settings2.bannerAuthorized)
        XCTAssertEqual(revoked.requests, 1)

        await vm.refreshBannerAuthorization()
        XCTAssertEqual(port.requests, 1, "re-reading the state prompted the person again")
    }

    /// Building the page must ask macOS nothing at all.
    ///
    /// The permission is requested when the person picks the mode and at no
    /// other time — and a settings page that reached the notification centre
    /// while being constructed would not merely prompt: it would end this run,
    /// because `UNUserNotificationCenter.current()` raises outside an app
    /// bundle. This walks the real path the app takes, descriptor included.
    func testTheSettingsPageIsBuiltWithoutAskingMacOSAnything() {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        _ = descriptor.settingsPage(host)
        XCTAssertNil(descriptor.viewModel(host).bannerAuthorization,
                     "building the page asked macOS about banners")
    }

    /// Without a port there is nothing to ask, and nothing to post — the
    /// descriptor is the only place that supplies one, and a forgotten wire
    /// there leaves the banner mode permanently mute while every test holding
    /// its own fake still passes.
    func testTheDescriptorGivesItsViewModelAWayToReachMacOS() {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        XCTAssertTrue(descriptor.viewModel(host).reachesBanners,
                      "the module's own view model cannot reach macOS at all")
    }
}
