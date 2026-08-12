// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import SwiftUI
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The three notice cards are pictures of what the setting does, and for a
/// while the loudest one was a picture of something else: `.system` was drawn
/// with a name in the menu bar, while `VPNNotice.showsMenuBarName` is
/// `self == .menuBar`. The picture and the enum agreed about nothing because
/// nothing connected them.
///
/// Two guards, because the defect had two halves. The drawing now derives from
/// the mode (`NoticePreview.of`), and these tests fail if either the derivation
/// or the call sites go back to describing the mode by hand.
@MainActor
final class ThePreviewDrawsWhatTheModeDoesTests: XCTestCase {

    /// The menu-bar band of a card, measured. `.menuBar` puts a name there and
    /// `.system` does not, so the quiet mode's band is the floor and the named
    /// mode's is strictly more ink.
    private func menuBarInk(_ mode: VPNNotice, _ appearance: NSAppearance.Name) throws -> Int {
        let m = MountedRender(NoticePreview.of(mode).frame(width: 104, height: 66),
                              width: 104, height: 66, appearance: appearance)
        m.settle()
        // The bar is the top fifth of the card; the banner starts below it.
        let ink = try XCTUnwrap(m.ink(0...13), "nothing drew in the menu-bar band")
        m.drop()
        return ink
    }

    func testOnlyTheMenuBarModePutsANameBesideTheIcon() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let silent = try menuBarInk(.silent, appearance)
            let named = try menuBarInk(.menuBar, appearance)
            let system = try menuBarInk(.system, appearance)

            XCTAssertGreaterThan(named, silent,
                                 "\(screen): the menu-bar mode draws a name, so its band cannot match the silent one")
            // The point of the whole file: the loudest mode is quiet *here*.
            XCTAssertEqual(system, silent,
                           "\(screen): `.system` draws no name in the menu bar — a banner names the configuration in words")
        }
    }

    /// `showsMenuBarName`/`postsBanner` are the only description of the modes,
    /// and the page must not carry a second one. The same rule a command name
    /// follows: a constant both sides read, never a literal typed twice.
    func testThePageDerivesThePicturesRatherThanDescribingThem() throws {
        let page = RepoSource.root
            .appendingPathComponent("Sources/Modules/VPN/UI/VPNSettingsPage.swift")
        let source = try String(contentsOf: page, encoding: .utf8)
        XCTAssertTrue(source.contains("NoticePreview.of("),
                      "the cards should be derived from the mode")
        XCTAssertFalse(source.contains("NoticePreview.strip(name:"),
                       "a hand-written pair of booleans beside a mode is the defect this file exists for")
    }
}
