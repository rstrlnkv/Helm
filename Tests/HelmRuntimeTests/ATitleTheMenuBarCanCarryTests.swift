// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime

/// The one string in the menu bar that a person — or a plist — wrote.
///
/// Every other part of the status item is drawn from the app's own vocabulary: a
/// glyph, a tint, a countdown of its own arithmetic. A VPN configuration's name
/// is free text, arrives through `scutil --nc list`, and was handed to the
/// status item verbatim: a 4000-character name parses perfectly well and is
/// 39 238 pt wide at the font the item draws with — twenty-six times the width
/// of the narrowest built-in display, for the three seconds the name is shown.
/// Measured with `NSFont.monospacedDigitSystemFont(ofSize:
/// NSFont.smallSystemFontSize, weight: .medium)`, which is the font
/// `StatusItemController` sets.
final class ATitleTheMenuBarCanCarryTests: XCTestCase {

    func testAnOrdinaryNameIsUntouched() {
        XCTAssertEqual(StatusPlan.menuBarTitle("Office"), "Office")
    }

    func testALongNameIsBoundedAndSaysThatItWasCut() {
        let title = StatusPlan.menuBarTitle(String(repeating: "M", count: 4000))
        XCTAssertNotNil(title)
        XCTAssertLessThanOrEqual(title?.count ?? .max, 24,
                                 "the menu bar was given \(title?.count ?? 0) characters to draw")
        XCTAssertEqual(title?.last, "…", "a name that was cut has to look cut")
    }

    /// A newline in the title is not merely long: `NSAttributedString` in a
    /// status item draws it, and the item's height is the menu bar's.
    func testNewlinesAndControlCharactersAreStripped() {
        let title = StatusPlan.menuBarTitle("Off\nice\u{7}\t")
        XCTAssertEqual(title, "Office")
    }

    /// Nothing to draw is `nil`, not an empty string: `choose` picks the first
    /// module with a title, and an empty one claims the slot from a module that
    /// has something to say.
    func testATitleOfNothingIsNoTitle() {
        XCTAssertNil(StatusPlan.menuBarTitle("\n\n"))
        XCTAssertNil(StatusPlan.menuBarTitle("   "))
    }
}
