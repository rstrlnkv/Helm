// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **A mode label that does not fit its control is a control that does not say
/// what it is set to.**
///
/// It used to be a caption under a picture card, and the defect was a label that
/// wrapped onto two lines: «Name in menu bar» was 117.9 pt in German, 125.0 in
/// Portuguese, 147.3 in Spanish and 148.7 in French against a 104 pt card. The
/// three modes are a pop-up's items now (C2), so the same string cannot wrap —
/// it truncates instead, which is the quieter half of the same fault.
///
/// Measured against **a real `NSPopUpButton` carrying the same titles and the
/// same glyphs**, not against the arithmetic the card sizes itself with: two
/// sides reading one helper is a check that cannot fail, and the glyph is
/// exactly what that helper does not know about — `HelmPickerWidth` is
/// calibrated on a pop-up of words, and a symbol column is 15…22 pt more.
///
/// Parameterized by language, never `AppLanguage.current`: the offender here is
/// French and this machine is not.
final class TheNoticeLabelsFitTheCardTests: XCTestCase {

    /// What AppKit itself says a pop-up holding these items needs.
    @MainActor
    private func needed(_ items: [(label: String, symbol: String)]) -> CGFloat {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in items {
            button.addItem(withTitle: item.label)
            button.lastItem?.image = NSImage(systemSymbolName: item.symbol,
                                             accessibilityDescription: nil)
        }
        button.sizeToFit()
        return button.fittingSize.width
    }

    @MainActor
    private func needed(in language: AppLanguage) -> CGFloat {
        needed(VPNNotice.allCases.map { (VPNStr.noticeOption($0, language: language),
                                         VPNNoticeGlyph.of($0)) })
    }

    @MainActor
    func testEveryNoticeLabelFitsItsPopUpInEveryLanguage() {
        var offenders: [String] = []
        for language in AppLanguage.allCases {
            let given = VPNConnectionCard.modeWidth(language: language)
            let wanted = needed(in: language)
            if wanted > given {
                offenders.append("  \(language.rawValue): the pop-up asks "
                                 + "\(String(format: "%.1f", wanted)) pt and is given \(given)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) language(s) draw a mode pop-up narrower than its own "
                      + "items, so the control truncates what it is set to:\n"
                      + offenders.sorted().joined(separator: "\n"))
    }

    /// The measurement this file is worth nothing without: that the instrument
    /// still sees a label the control cannot hold. The eight real label sets
    /// have 3.2 pt of slack at their worst, which is close enough to the width
    /// that a threshold above every real case would look exactly like a pass.
    @MainActor
    func testTheInstrumentStillFailsTheLabelThisReplaced() {
        // The French of the key that was deleted, as it shipped in 0.9.0.
        let old = needed([("Rien", "bell.slash"),
                          ("Nom dans la barre des menus", "menubar.arrow.up.rectangle"),
                          ("Notification", "bell.badge")])
        XCTAssertGreaterThan(old, VPNConnectionCard.modeWidth(language: .fr),
                             "the measurement no longer sees a label that was two lines on "
                             + "screen, so a pass above says nothing")
    }
}
