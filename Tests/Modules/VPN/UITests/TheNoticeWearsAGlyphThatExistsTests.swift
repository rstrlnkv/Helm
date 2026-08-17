// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import AppKit
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// A misspelled SF Symbol draws nothing: the door keeps its frame and loses its
/// face, which no compiler catches. Same guard `TheCardWearsAGlyphThatExists`
/// holds for the verb.
final class TheNoticeWearsAGlyphThatExistsTests: XCTestCase {

    func testEveryModeOffersASymbolMacOSHas() {
        for mode in [VPNNotice.silent, .menuBar, .system] {
            let name = VPNNoticeGlyph.of(mode)
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "\(mode) is drawn with \"\(name)\", which SF Symbols does not have")
        }
    }

    /// Three modes, three faces. Two modes sharing a glyph is a door that cannot
    /// say what it is set to.
    func testTheThreeModesDoNotShareAFace() {
        let faces = Set([VPNNotice.silent, .menuBar, .system].map(VPNNoticeGlyph.of))
        XCTAssertEqual(faces.count, 3)
    }
}
